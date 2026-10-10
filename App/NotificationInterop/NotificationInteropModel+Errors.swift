// SPDX-License-Identifier: MPL-2.0
import AccessoryNotifications
import AccessorySetupKit
import CoreBluetooth
import Foundation
import OSLog

@available(iOS 26.5, *)
extension NotificationInteropModel {
    func report(_ error: any Error) {
        recordNotificationError(error, operation: "userAction")
        let nsError = error as NSError
        if nsError.domain == ASErrorDomain && nsError.code == ASError.Code.userCancelled.rawValue {
            notice = "已取消操作，可以稍后再试。"
            return
        }
        if nsError.domain == ASErrorDomain && nsError.code == ASError.Code.pickerRestricted.rawValue {
            notice = "系统暂不允许显示配件选择器。请保持 DuaLink 在前台后重试。"
            return
        }
        if let typed = error as? AccessoryError {
            switch typed {
            case .unsupportedAccessory:
                notificationUnsupportedAccessory = true
                notice = "系统暂不支持向当前登记的设备申请通知转发。请点“管理通知权限”检查这台设备已有的系统设置。"
                return
            case .unsupportedPlatform:
                notificationUnavailable = true
                notice = "当前设备或系统不支持通知转发。此功能需要受支持的 iPhone 与 iOS 版本。"
                return
            case .accessoryNotificationsUnavailable:
                notificationUnavailable = true
                notice = "通知转发在当前系统配置下不可用。请查看使用条件和系统配件设置。"
                return
            default: break
            }
        }
        notice = "操作未完成。请确认鸿蒙已开启通知同步和通知回复，保持蓝牙开启后重试。"
    }

    /// Read-only metadata for diagnosis. Never log device UUIDs, bridge address
    /// bytes, display names, userInfo, localized descriptions or notification data.
    func recordNotificationError(_ error: any Error, operation: String) {
        let systemError = error as NSError
        technicalDetail = "\(systemError.domain) / \(systemError.code)"
        let typedCase: String
        if let typed = error as? AccessoryError {
            switch typed {
            case .unsupportedAccessory: typedCase = "unsupportedAccessory"
            case .unsupportedPlatform: typedCase = "unsupportedPlatform"
            case .accessoryNotificationsUnavailable: typedCase = "accessoryNotificationsUnavailable"
            case .invalidNotificationResponse: typedCase = "invalidNotificationResponse"
            case .coordinationTimeout: typedCase = "coordinationTimeout"
            case .internalInconsistency: typedCase = "internalInconsistency"
            @unknown default: typedCase = "unknownAccessoryError"
            }
        } else {
            typedCase = "otherError"
        }
        logger.error("Notification \(operation, privacy: .public) failed: \(typedCase, privacy: .public), \(self.technicalDetail, privacy: .public)")
        #if DEBUG
        let defaults = UserDefaults.standard
        defaults.set(technicalDetail, forKey: "interop.debug.lastError")
        defaults.set(typedCase, forKey: "interop.debug.lastErrorTypedCase")
        defaults.set(operation, forKey: "interop.debug.lastErrorOperation")
        defaults.removeObject(forKey: "interop.debug.errorDescription")
        defaults.removeObject(forKey: "interop.debug.errorReason")
        if let accessory {
            let descriptor = accessory.descriptor
            defaults.set([
                "state": accessory.state.rawValue,
                "hasBTIdentifier": accessory.bluetoothIdentifier != nil,
                "bridgeIdentifierByteCount": accessory.bluetoothTransportBridgingIdentifier?.count ?? 0,
                "serviceUUID": descriptor.bluetoothServiceUUID?.uuidString ?? "none",
                "supportedOptions": descriptor.supportedOptions.rawValue,
                "companyId": descriptor.bluetoothCompanyIdentifier.rawValue
            ], forKey: "interop.debug.errorAccessoryShape")
        } else {
            defaults.removeObject(forKey: "interop.debug.errorAccessoryShape")
        }
        #endif
    }
}
