// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Use names supplied by the device, never a model inferred from a BLE identifier.
nonisolated enum NotificationAccessoryName {
    static func display(advertised: String?, discovered: String?) -> String {
        for value in [advertised, discovered] {
            guard let value else { continue }
            let cleaned = value.components(separatedBy: .controlCharacters).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !cleaned.contains("通知实验"), cleaned != "DuaLink 鸿蒙手机" else { continue }
            return String(cleaned.prefix(64))
        }
        return "鸿蒙手机"
    }
}
