// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationLabCore

@Test func receivingReplySurvivesAnOverlappingNotificationBatch() throws {
    let reply = LabEnvelope(kind: .ciphertext, sessionID: UUID(), payload: Data("回复分片🙂".utf8))
    let bytes = try LabFrameCodec.encode(reply)
    var receive = LabReceiveBuffer()
    var subscription = LabSubscriptionState()
    _ = subscription.prepare(isData: true, isNotifying: false)
    _ = subscription.observed(isNotifying: true)
    #expect(try receive.append(Data(bytes.prefix(20))).isEmpty)
    #expect(receive.hasPendingFrame)
    let oldTimeout = receive.generation
    // Encoding an outgoing batch must not alter the active receive stream or
    // emit an unsubscribe, even if characteristic discovery is repeated.
    _ = try LabFrameCodec.encode(LabEnvelope(kind: .ciphertext, sessionID: UUID(), payload: Data([42])))
    #expect(subscription.prepare(isData: true, isNotifying: true) == .none)
    let decoded = try receive.append(Data(bytes.dropFirst(20)))
    #expect(decoded.count == 1)
    #expect(decoded.first?.sessionID == reply.sessionID)
    #expect(decoded.first?.payload == reply.payload)
    #expect(!receive.shouldExpire(oldTimeout))
    #expect(!receive.hasPendingFrame)
}

@Test func fragmentProgressInvalidatesOldTimeoutButEmptyUpdatesDoNot() throws {
    var buffer = LabReceiveBuffer()
    let frame = try LabFrameCodec.encode(LabEnvelope(kind: .security, payload: Data([1, 2])))
    _ = try buffer.append(Data(frame.prefix(1)))
    let old = buffer.generation
    #expect(buffer.shouldExpire(old))
    _ = try buffer.append(Data(frame.dropFirst(1).prefix(1)))
    #expect(!buffer.shouldExpire(old))
    let current = buffer.generation
    _ = try buffer.append(Data())
    #expect(buffer.shouldExpire(current))
    _ = try buffer.append(Data(frame.dropFirst(2)))
    #expect(!buffer.shouldExpire(current))
}

@Test func resetDropsPartialBytesAndInvalidatesOldTimeout() throws {
    var buffer = LabReceiveBuffer()
    let frame = try LabFrameCodec.encode(LabEnvelope(kind: .security, payload: Data([1])))
    _ = try buffer.append(Data(frame.prefix(7)))
    let old = buffer.generation
    buffer.reset()
    #expect(!buffer.shouldExpire(old))
    #expect(try buffer.append(frame).count == 1)
    #expect(!buffer.hasPendingFrame)
}

@Test func completeAndPartialFramesInOneUpdateRetainTheirOwnTimeout() throws {
    var buffer = LabReceiveBuffer()
    let frame = try LabFrameCodec.encode(LabEnvelope(kind: .security, payload: Data([1])))
    #expect(try buffer.append(frame + frame.prefix(2)).count == 1)
    #expect(buffer.shouldExpire(buffer.generation))
    #expect(try buffer.append(Data(frame.dropFirst(2))).count == 1)
    #expect(!buffer.hasPendingFrame)
}

@Test func partialReplyPreventsSilentRecoveryAcrossAllBoundaries() throws {
    var buffer = LabReceiveBuffer()
    _ = try buffer.append(Data([0, 0]))
    var policy = LabReconnectPolicy()
    #expect(!LabReconnectPolicy.canResume(writeOffsets: [0], waitingForWrite: false,
                                         hasPendingReceive: buffer.hasPendingFrame))
    #expect(policy.beginRecovery(writeOffsets: [0], waitingForWrite: false,
                                  hasPendingReceive: buffer.hasPendingFrame) == false)
    #expect(policy.beginProfileRecovery(writeOffsets: [0], waitingForWrite: false,
                                         hasPendingReceive: buffer.hasPendingFrame) == false)
    #expect(policy.attempts == 0)
    buffer.reset()
    #expect(policy.beginRecovery(writeOffsets: [0], waitingForWrite: false,
                                 hasPendingReceive: buffer.hasPendingFrame) == true)
}
