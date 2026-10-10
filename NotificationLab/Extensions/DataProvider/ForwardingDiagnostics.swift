// SPDX-License-Identifier: MPL-2.0
import AccessoryLiveActivities
import AccessoryTransportExtension
import CryptoKit
import Foundation

/// Shipping diagnostics describe delivery boundaries, never activity IDs,
/// titles, content states, location, or notification/reply text.
enum ForwardingDiagnostics {
    static func session(_ session: some AccessoryFeatureSession, component: String) {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        if #available(iOS 27.0, *) {
            let accessory = session.accessory
            // Match the main app and transport's approved-target fingerprint.
            let target = accessory.bluetoothIdentifier.map {
                digest("DuaLink approved target v1:\($0.uuidString.uppercased())")
            } ?? "none"
            let sessionHash = digest("DuaLink feature session v1:\(session.sessionID.uuidString)")
            LabDiagnostics.record(component, "系统转发会话绑定",
                detail: "build=\(build), target=\(target), session=\(sessionHash), authorized=\(accessory.state == .authorized)")
        } else {
            LabDiagnostics.record(component, "系统转发会话绑定",
                detail: "build=\(build), identityAPI=unavailable")
        }
    }

    static func snapshot(_ activities: [AccessoryLiveActivity]) {
        LabDiagnostics.record("activity", "系统实时活动快照",
                              detail: "total=\(activities.count)")
        for (source, items) in Dictionary(grouping: activities, by: \.sourceBundleIdentifier) {
            LabDiagnostics.record("activity", "实时活动快照来源",
                detail: "sourceHash=\(sourceHash(source)), count=\(items.count), content=\(items.filter { $0.content != nil }.count), alert=\(items.filter { $0.content?.alert != nil }.count)")
        }
    }

    static func callback(_ activity: AccessoryLiveActivity, alert: Bool, activeSession: Bool) {
        LabDiagnostics.record("activity", "收到系统实时活动回调",
            detail: "sourceHash=\(sourceHash(activity.sourceBundleIdentifier)), state=\(activity.state), alertCallback=\(alert), activeSession=\(activeSession), hasContent=\(activity.content != nil), hasAlert=\(activity.content?.alert != nil)")
    }

    private static func sourceHash(_ source: String) -> String {
        digest("DuaLink activity source v1:\(source)")
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
