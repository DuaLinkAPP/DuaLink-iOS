// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
import UIKit

@available(iOS 26.5, *)
extension NotificationInteropModel {
    func renameSystemAccessory() {
        guard canManage, let accessory, let session else { return }
        stopReconnect()
        guard NotificationSetupLease.shared.begin() else {
            notice = "其他设备连接正在使用蓝牙，请稍后再修改系统名称。"
            return
        }
        // ASK saves the system accessory label. An app-local alias cannot change it.
        UIPasteboard.general.string = deviceName(for: accessory)
        notice = "真实设备名称已复制，请在系统改名窗口粘贴并保存。"
        busy = true
        let attempt = UUID()
        renameAttempt = attempt
        let revision = generation
        // Recover the UI if the system never presents its rename sheet. Once
        // pickerSetupRename arrives, the user may take as long as needed to edit.
        renameTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            guard let self, self.renameAttempt == attempt, self.generation == revision else { return }
            self.finishRenameLease()
            self.generation += 1
            self.ready = false
            self.session = nil
            self.checkTask?.cancel(); self.checkTask = nil
            session.invalidate()
            self.busy = false
            self.notice = "系统改名窗口未能打开。可在 iPhone 设置 → 蓝牙 → 设备详情 → 名称中修改，无需取消配对。"
        }
        session.renameAccessory(accessory, options: []) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.renameAttempt == attempt, self.generation == revision else { return }
                self.finishRenameLease()
                self.busy = false
                self.accessories = session.accessories
                if let error { self.report(error) }
                else { self.notice = nil }
                self.refreshDeviceNames()
            }
        }
    }

    func finishRenameLease() {
        guard renameAttempt != nil else { return }
        renameAttempt = nil
        renameTimeout?.cancel(); renameTimeout = nil
        NotificationSetupLease.shared.end()
    }
}
