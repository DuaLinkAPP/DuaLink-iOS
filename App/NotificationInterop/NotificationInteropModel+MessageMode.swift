// SPDX-License-Identifier: MPL-2.0
import Foundation

@available(iOS 26.5, *)
extension NotificationInteropModel {
    func selectMessageMode(_ mode: InteropMessageMode) {
        guard messageMode != mode else { return }
        do {
            try InteropModeStore.product.select(mode)
            messageMode = mode
            authorizationRevision += 1
            // Close only the app's inspection connection; platform permissions and pairing stay explicit.
            stopReconnect()
            cancelPermissionCheck()
            connectionNotice = nil
            notice = nil
            if mode == .notificationReply { start() }
        } catch {
            notice = "模式未能保存，请稍后重试。"
        }
    }

    var notificationModeEnabled: Bool {
        messageMode == .notificationReply && InteropModeStore.product.allowsNotifications()
    }
}
