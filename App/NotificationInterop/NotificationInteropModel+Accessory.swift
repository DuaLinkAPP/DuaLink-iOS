// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
import CoreBluetooth
import UIKit

@available(iOS 26.5, *)
extension NotificationInteropModel {
    func addAccessory(authorizeAfterAdding: Bool = false) {
        guard notificationModeEnabled, ready, !busy, let session else { return }
        guard UIApplication.shared.applicationState == .active,
              UIApplication.shared.connectedScenes.contains(where: { $0.activationState == .foregroundActive }) else {
            notice = "请保持 DuaLink 在前台，再点添加手机。"; return
        }
        guard accessories.isEmpty else {
            notice = "这台手机已添加，请直接管理通知权限，无需重复添加。"; return
        }
        guard NotificationSetupLease.shared.begin() else {
            notice = "主 App 正在使用另一台设备，请结束该连接后再添加手机。无需取消系统配对。"; return
        }
        // Restore direct system discovery. First-time setup must not depend on
        // a CoreBluetooth pre-scan, a readable device name or a migration identifier.
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: "F6E14D00-5D19-4CBD-A47D-19DBD8245E01")
        descriptor.supportedOptions = []
        let settings = ASPickerDisplaySettings()
        // Let ASK aggregate advertising + scan-response data and render its
        // native hardware-name subtitle. Rebuilding a discovered display item
        // from an early event can discard information that arrives later.
        settings.options = []
        settings.discoveryTimeout = .medium
        session.pickerDisplaySettings = settings
        let item = ASPickerDisplayItem(name: "DuaLink", productImage: accessoryArtwork(), descriptor: descriptor)
        let revision = generation
        busy = true
        notice = nil
        session.showPicker(for: [item]) { [weak self] error in
            Task { @MainActor [weak self] in
                NotificationSetupLease.shared.end()
                guard let self, self.generation == revision else { return }
                self.busy = false
                self.accessories = session.accessories
                self.resolvePermissionDevice()
                self.refreshDeviceNames()
                if error == nil { self.connectAutomaticallyIfEligible() }
                if let error { self.report(error) }
                else if self.accessories.isEmpty { self.notice = "尚未添加设备，可再次尝试。" }
                if self.notificationModeEnabled, error == nil, authorizeAfterAdding, let accessory = self.accessory,
                   accessory.state == .authorized {
                    self.refreshPending = false
                    await self.requestPermission(accessory)
                } else { self.refresh() }
            }
        }
    }

    private func accessoryArtwork() -> UIImage {
        UIImage(named: "NotificationAccessoryArtwork") ??
            UIImage(systemName: "iphone", withConfiguration: UIImage.SymbolConfiguration(pointSize: 256)) ?? UIImage()
    }
}
