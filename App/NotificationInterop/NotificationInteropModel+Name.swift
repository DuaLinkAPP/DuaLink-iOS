// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
import Foundation

@available(iOS 26.5, *)
extension NotificationInteropModel {
    /// Persist the authorized accessory's system display name against its ID.
    /// Never associate a newly paired phone with a single global "last seen" name.
    func refreshDeviceNames() {
        for accessory in accessories {
            guard let identifier = accessory.bluetoothIdentifier else { continue }
            let name = accessory.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name != "鸿蒙手机", !name.contains("通知实验") else { continue }
            deviceNames[identifier.uuidString] = String(name.prefix(64))
        }
        UserDefaults.standard.set(deviceNames, forKey: "interop.deviceNames")
    }

    func deviceName(for accessory: ASAccessory) -> String {
        if let identifier = accessory.bluetoothIdentifier,
           let actualName = deviceNames[identifier.uuidString] { return actualName }
        // This standalone companion uses the ASK record directly. It has no
        // separate commercial BLE manager from which to resolve another name.
        return accessory.displayName
    }
}
