// SPDX-License-Identifier: MPL-2.0
import CoreBluetooth
import Foundation

/// User-facing connection results contain only reviewed copy. System error
/// descriptions stay in diagnostics and never imply successful data delivery.
nonisolated enum NotificationConnectionNotice {
    enum Reason: Sendable {
        case setupInProgress, unavailable, timedOut, disconnected
        case serviceMissing, pairingChanged, encryptionTimedOut, cancelled, unknown
    }

    static let serviceFound = "已找到鸿蒙通知服务，尚未确认回复通道。请查看鸿蒙端是否显示回复已就绪。"

    static func message(for reason: Reason) -> String {
        switch reason {
        case .setupInProgress:
            "手机设置尚未完成，请完成系统配件设置后再连接。"
        case .unavailable:
            "蓝牙暂不可用。请确认两台手机的蓝牙已开启，并允许 DuaLink 使用蓝牙。"
        case .timedOut:
            "连接未完成。请确认两端都选择“通知回复”，打开鸿蒙 DuaLink 后重试。"
        case .disconnected:
            "连接已中断。请让两台手机靠近，保持蓝牙开启后重试。"
        case .serviceMissing:
            "蓝牙已连通，但通知服务未就绪。请先确认鸿蒙也选择了“通知回复”并已开始连接。"
        case .pairingChanged:
            "配对信息暂时不一致。请先确认两台手机的系统蓝牙配对状态，再重试连接。"
        case .encryptionTimedOut:
            "安全连接暂未恢复。请保持两台手机靠近并打开鸿蒙 DuaLink，稍后重试。"
        case .cancelled:
            "本次连接已取消，可以稍后重试。"
        case .unknown:
            "连接暂未恢复。请确认两台手机的蓝牙已开启，打开鸿蒙 DuaLink 后重试。"
        }
    }

    /// Match documented domain/code pairs, never English error descriptions.
    static func systemFailure(_ error: NSError) -> String {
        guard error.domain == CBErrorDomain else { return message(for: .unknown) }
        let reason: Reason
        switch error.code {
        case CBError.Code.connectionTimeout.rawValue: reason = .timedOut
        case CBError.Code.notConnected.rawValue, CBError.Code.peripheralDisconnected.rawValue:
            reason = .disconnected
        case CBError.Code.peerRemovedPairingInformation.rawValue: reason = .pairingChanged
        case CBError.Code.encryptionTimedOut.rawValue: reason = .encryptionTimedOut
        case CBError.Code.operationCancelled.rawValue: reason = .cancelled
        default: reason = .unknown
        }
        return message(for: reason)
    }
}

/// System profile activation is explicit; routine GATT checks must stay neutral.
nonisolated enum NotificationReconnectMode: Equatable, Sendable {
    case notificationService, systemServices

    var requestsANCS: Bool { self == .systemServices }
    var enablesTransportBridging: Bool { self == .systemServices }

    func options(ancsKey: String, bridgingKey: String) -> [String: Bool] {
        guard self == .systemServices else { return [:] }
        return [ancsKey: requestsANCS, bridgingKey: enablesTransportBridging]
    }
}

extension NotificationConnectionNotice {
    static func systemServicesFound(ancsAuthorized: Bool) -> String {
        if ancsAuthorized {
            return "已找到鸿蒙通知服务，系统通知共享已允许。通知转发权限会单独检查。"
        }
        return "已找到鸿蒙通知服务，系统通知共享尚未允许。请处理 iPhone 的系统授权提示；通知转发权限会单独检查。"
    }
}
