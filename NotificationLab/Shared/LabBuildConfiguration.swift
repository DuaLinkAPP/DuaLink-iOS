// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Every executable receives the same App Group from its build configuration.
/// A new developer never needs the original publisher's group or Team ID.
nonisolated enum LabBuildConfiguration {
    static var notificationAppGroup: String {
        appGroup(from: Bundle.main.infoDictionary)
    }

    static func appGroup(from info: [String: Any]?) -> String {
        guard let value = info?["DuaLinkNotificationAppGroup"] as? String,
              value.hasPrefix("group."), !value.contains("$("),
              !value.contains(where: { $0.isWhitespace }) else {
            // Host tests have no application Info.plist. This public namespace
            // is a fallback, never a developer's private signing identity.
            return "group.org.dualink.opensource.notifications"
        }
        return value
    }
}
