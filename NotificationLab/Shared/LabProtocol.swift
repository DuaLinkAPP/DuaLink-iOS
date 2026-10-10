// SPDX-License-Identifier: MPL-2.0
import Foundation

/// 独立实验协议；不能把 ANCS 的 32 位 UID 用作此通道的通知标识。
nonisolated enum LabProtocol {
    static let version = 1
    static let service = "F6E14D00-5D19-4CBD-A47D-19DBD8245E01"
    static let dataToAccessory = "F6E14D01-5D19-4CBD-A47D-19DBD8245E01"
    static let dataFromAccessory = "F6E14D02-5D19-4CBD-A47D-19DBD8245E01"
    static let keyToAccessory = "F6E14D03-5D19-4CBD-A47D-19DBD8245E01"
    static let keyFromAccessory = "F6E14D04-5D19-4CBD-A47D-19DBD8245E01"
    static var appGroup: String { LabBuildConfiguration.notificationAppGroup }
    static let maxFrameBytes = 128 * 1024
    static let maxReplyBytes = 2048
    static let maxPendingWriteFrames = 256
    static let maxPendingWriteBytes = 2 * 1024 * 1024

    /// Bound startup bursts without integer overflow or an unbounded BLE backlog.
    static func canQueueFrame(pendingFrames: Int, pendingBytes: Int, frameBytes: Int) -> Bool {
        guard pendingFrames >= 0, pendingFrames < maxPendingWriteFrames,
              pendingBytes >= 0, pendingBytes <= maxPendingWriteBytes, frameBytes > 0 else { return false }
        return frameBytes <= maxPendingWriteBytes - pendingBytes
    }
}

nonisolated struct LabNotificationKey: Codable, Hashable, Sendable {
    let sourceIdentifier: String
    let notificationIdentifier: String
}

nonisolated struct LabAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case button, textInput, dismiss }
    let identifier: String
    let title: String
    let kind: Kind
    let placeholder: String?
}

nonisolated struct LabNotification: Codable, Sendable {
    let key: LabNotificationKey
    let sourceName: String
    let title: String
    let subtitle: String
    let body: String
    let deliveredAt: Date
    let shouldAlert: Bool
    let actions: [LabAction]
}

nonisolated struct LabLiveActivity: Codable, Sendable {
    let activityIdentifier: String
    let sourceBundleIdentifier: String
    let sourceBundleName: String
    let state: String
    let alertTitle: String?
    let alertBody: String?
    let shouldAlert: Bool
}

/// 经系统加密前的业务消息。通知正文仅通过受保护通道发往配件，不写入 App Group。
nonisolated struct LabEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case added, updated, removed, removeAll, result
        case activityUpdated, activityAlert, activityRemoved, activitySnapshot
    }
    var version = LabProtocol.version
    let kind: Kind
    var notification: LabNotification?
    var key: LabNotificationKey?
    var liveActivity: LabLiveActivity?
    var liveActivities: [LabLiveActivity]?
    var activityStreamID: UUID?
    var activityRevision: Int?
    var requestID: UUID?
    var result: String?
}

nonisolated struct LabResponse: Codable, Sendable {
    let version: Int
    let requestID: UUID
    let key: LabNotificationKey
    let actionIdentifier: String
    let userText: String?

    func validate(against notification: LabNotification) throws {
        guard version == LabProtocol.version else { throw LabProtocolError.unsupportedVersion }
        guard key == notification.key else { throw LabProtocolError.unknownNotification }
        guard let action = notification.actions.first(where: { $0.identifier == actionIdentifier }) else {
            throw LabProtocolError.unknownAction
        }
        if action.kind == .textInput {
            guard let userText, !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  userText.utf8.count <= LabProtocol.maxReplyBytes else {
                throw LabProtocolError.invalidText
            }
        } else if userText != nil {
            throw LabProtocolError.unexpectedText
        }
    }
}

/// BLE 外层只承载密文或公开的密钥交换材料；不允许直接发送明文回复。
nonisolated struct LabEnvelope: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case ciphertext, security }
    var version = LabProtocol.version
    let kind: Kind
    var sessionID: UUID?
    let payload: Data
}

nonisolated struct LabSecurityPayload: Codable, Sendable {
    let keyType: String
    let cipherSuite: String
    let version: String
    let key: Data
    let identifier: String?
    // Cryptographic context is opaque: SDK descriptions can differ in case from
    // the canonical algorithm tokens used to validate this wire protocol.
    var protocolInfo: String? = nil
}

nonisolated enum LabProtocolError: String, Error, Sendable {
    case unsupportedVersion, invalidFrame, frameTooLarge, unknownNotification, unknownAction
    case invalidText, unexpectedText, invalidKey, unavailable, timedOut, queueFull
}
