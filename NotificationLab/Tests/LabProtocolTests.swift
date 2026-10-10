// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationLabCore

@Test func frameSurvivesEveryFragmentBoundary() throws {
    let message = LabEnvelope(kind: .ciphertext, sessionID: UUID(), payload: Data("分片测试🙂".utf8))
    let bytes = try LabFrameCodec.encode(message)
    for boundary in 1..<bytes.count {
        var codec = LabFrameCodec()
        #expect(try codec.append(Data(bytes.prefix(boundary))).isEmpty)
        let decoded = try #require(codec.append(Data(bytes.dropFirst(boundary))).first)
        #expect(decoded.sessionID == message.sessionID)
        #expect(decoded.payload == message.payload)
    }
}

@Test func coalescedFramesAndTruncatedTail() throws {
    let a = LabEnvelope(kind: .security, payload: Data([1, 2, 3]))
    let b = LabEnvelope(kind: .ciphertext, sessionID: UUID(), payload: Data([4]))
    let first = try LabFrameCodec.encode(a)
    let second = try LabFrameCodec.encode(b)
    var codec = LabFrameCodec()
    #expect(try codec.append(first + second.prefix(7)).map(\.kind) == [.security])
    #expect(try codec.append(Data(second.dropFirst(7))).map(\.kind) == [.ciphertext])
}

@Test func rejectsOversizedFramesAndResetsAssembly() throws {
    var codec = LabFrameCodec()
    #expect(throws: LabProtocolError.invalidFrame) { try codec.append(Data([0x7f, 0xff, 0xff, 0xff])) }
    let frame = try LabFrameCodec.encode(LabEnvelope(kind: .security, payload: Data()))
    #expect(try codec.append(frame).count == 1)
}

@Test func rejectsUnsupportedWireVersion() throws {
    var codec = LabFrameCodec()
    let frame = try LabFrameCodec.encode(LabEnvelope(version: 99, kind: .security, payload: Data()))
    #expect(throws: LabProtocolError.unsupportedVersion) { try codec.append(frame) }
}

@Test func securityPayloadKeepsSDKProtocolInfoIndependentOfWireAlgorithmToken() throws {
    let info = "P256-Version1-00000000-0000-0000-0000-000000000001"
    let payload = LabSecurityPayload(keyType: "encapsulatedKey", cipherSuite: "p256", version: "Version1",
        key: Data([1, 2, 3]), identifier: "00000000-0000-0000-0000-000000000001", protocolInfo: info)
    let decoded = try JSONDecoder().decode(LabSecurityPayload.self, from: JSONEncoder().encode(payload))
    #expect(decoded.cipherSuite == "p256")
    #expect(decoded.protocolInfo == info)

    let legacy = Data(#"{"keyType":"publicKey","cipherSuite":"p256","version":"Version1","key":"AQID"}"#.utf8)
    #expect(try JSONDecoder().decode(LabSecurityPayload.self, from: legacy).protocolInfo == nil)
}

@Test func startupBurstQueueAllows48FramesButKeepsCountAndByteLimits() {
    #expect(LabProtocol.canQueueFrame(pendingFrames: 47, pendingBytes: 47 * 1024, frameBytes: 1024))
    #expect(LabProtocol.canQueueFrame(pendingFrames: 255,
        pendingBytes: LabProtocol.maxPendingWriteBytes - 1024, frameBytes: 1024))
    #expect(!LabProtocol.canQueueFrame(pendingFrames: 256, pendingBytes: 256, frameBytes: 1))
    #expect(!LabProtocol.canQueueFrame(pendingFrames: 1,
        pendingBytes: LabProtocol.maxPendingWriteBytes - 1024, frameBytes: 1025))
    #expect(!LabProtocol.canQueueFrame(pendingFrames: 1, pendingBytes: Int.max, frameBytes: 1))
    #expect(!LabProtocol.canQueueFrame(pendingFrames: 0, pendingBytes: 0, frameBytes: Int.max))
    #expect(!LabProtocol.canQueueFrame(pendingFrames: 0, pendingBytes: -1, frameBytes: 1))
    #expect(LabProtocol.canQueueFrame(pendingFrames: 0, pendingBytes: 0, frameBytes: 1024))
}

private let key = LabNotificationKey(sourceIdentifier: "example.source", notificationIdentifier: "notification-1")
private func notification() -> LabNotification {
    LabNotification(key: key, sourceName: "Test", title: "Test", subtitle: "", body: "",
        deliveredAt: Date(), shouldAlert: true, actions: [
            LabAction(identifier: "reply", title: "回复", kind: .textInput, placeholder: ""),
            LabAction(identifier: "confirm", title: "确认", kind: .button, placeholder: nil)
        ])
}

@Test func validatesExactNotificationAndAction() throws {
    let reply = LabResponse(version: 1, requestID: UUID(), key: key, actionIdentifier: "reply", userText: "好的🙂")
    try reply.validate(against: notification())
    let mismatch = LabResponse(version: 1, requestID: UUID(),
        key: LabNotificationKey(sourceIdentifier: "other.app", notificationIdentifier: key.notificationIdentifier),
        actionIdentifier: "reply", userText: "好的")
    #expect(throws: LabProtocolError.unknownNotification) { try mismatch.validate(against: notification()) }
    let invented = LabResponse(version: 1, requestID: UUID(), key: key, actionIdentifier: "delete", userText: nil)
    #expect(throws: LabProtocolError.unknownAction) { try invented.validate(against: notification()) }
}

@Test(arguments: [nil, "", "  \n", String(repeating: "🙂", count: 513)])
func rejectsInvalidReplyText(_ text: String?) {
    let reply = LabResponse(version: 1, requestID: UUID(), key: key, actionIdentifier: "reply", userText: text)
    #expect(throws: LabProtocolError.invalidText) { try reply.validate(against: notification()) }
}

@Test func buttonActionsCannotSmuggleText() {
    let reply = LabResponse(version: 1, requestID: UUID(), key: key, actionIdentifier: "confirm", userText: "unexpected")
    #expect(throws: LabProtocolError.unexpectedText) { try reply.validate(against: notification()) }
}

@Test func duplicateRequestsNeverExecuteAgainEvenWhenLedgerIsFull() throws {
    var ledger = LabResponseLedger(capacity: 1)
    let id = UUID()
    #expect(try ledger.reserve(id) == nil)
    #expect(try ledger.reserve(id) == "pending")
    ledger.finish(id, result: "systemAccepted")
    #expect(try ledger.reserve(id) == "systemAccepted")
    #expect(throws: LabProtocolError.queueFull) { try ledger.reserve(UUID()) }
    #expect(try ledger.reserve(id) == "systemAccepted")
}
