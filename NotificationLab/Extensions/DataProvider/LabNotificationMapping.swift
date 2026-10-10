// SPDX-License-Identifier: MPL-2.0
import AccessoryNotifications
import Foundation

extension LabNotification {
    init(_ notification: AccessoryNotification, shouldAlert: Bool) {
        self.init(key: LabNotificationKey(sourceIdentifier: notification.identifier.sourceIdentifier,
                                         notificationIdentifier: notification.identifier.notificationIdentifier),
                  sourceName: notification.sourceName, title: notification.title ?? "",
                  subtitle: notification.subtitle ?? "", body: notification.body?.string ?? "",
                  deliveredAt: notification.deliveryDate, shouldAlert: shouldAlert,
                  actions: notification.actions.compactMap { action in
            switch action.type {
            case .background:
                return LabAction(identifier: action.identifier, title: action.title ?? "操作", kind: .button, placeholder: nil)
            case .dismiss:
                return LabAction(identifier: action.identifier, title: action.title ?? "关闭", kind: .dismiss, placeholder: nil)
            case .textInput(let placeholder):
                return LabAction(identifier: action.identifier, title: action.title ?? "回复", kind: .textInput, placeholder: placeholder)
            @unknown default: return nil
            }
        })
    }
}
