// SPDX-License-Identifier: MPL-2.0
import AccessoryLiveActivities
import AccessorySetupKit
import Foundation
import OSLog

/// Kept separately from notification authorization: each feature has its own
/// system permission, and neither permission proves that data was delivered.
nonisolated enum NotificationLiveActivityAuthorization: Sendable {
    case unknown, checking, allowed, limited, denied, undetermined, failed

    var title: String {
        switch self {
        case .unknown: "尚未检查实时活动权限"
        case .checking: "正在检查实时活动权限"
        case .allowed: "已允许实时活动转发"
        case .limited: "已允许部分 App 的实时活动"
        case .denied: "实时活动转发未开启"
        case .undetermined: "等待允许实时活动转发"
        case .failed: "当前实时活动权限待确认"
        }
    }

    var permitsForwarding: Bool { self == .allowed || self == .limited }
}

@available(iOS 26.5, *)
extension NotificationInteropModel {
    var liveActivityAuthorization: NotificationLiveActivityAuthorization {
        if let decision = liveActivityPermission.confirmed {
            switch decision {
            case .allowed: return .allowed
            case .limited: return .limited
            case .denied: return .denied
            case .undetermined: return .undetermined
            }
        }
        if liveActivityPermission.queryFailed { return .failed }
        return liveActivityPermission.isChecking ? .checking : .unknown
    }

    var liveActivityPermissionTitle: String {
        liveActivityPermission.historicalSummary ?? liveActivityAuthorization.title
    }

    /// Refresh silently alongside notifications; returning from Settings must
    /// never reopen the authorization sheet or occupy the user-action busy state.
    func checkLiveActivityAuthorization(_ accessory: ASAccessory, revision: Int, sessionGeneration: Int) async {
        guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
        let permissionRevision = liveActivityPermission.beginCheck()
        do {
            let result = try await LiveActivityForwarding.authorization(forAccessory: accessory)
            guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
            applyLiveActivityAuthorization(result, permissionRevision: permissionRevision)
        } catch {
            guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
            liveActivityPermission.failCheck(revision: permissionRevision)
            recordLiveActivityAuthorizationError(error, operation: "query")
        }
    }

    func manageLiveActivities() async {
        guard canManage, let accessory else { return }
        stopAutomaticConnectionIfNeeded()
        cancelPermissionCheck()
        let sessionGeneration = generation
        let revision = authorizationRevision
        busy = true
        permissionAction = .liveActivities
        defer {
            if generation == sessionGeneration {
                busy = false
                permissionAction = nil
                refresh()
            }
        }
        do {
            let result = try await LiveActivityForwarding.presentAuthorizationSheet(forAccessory: accessory)
            guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
            applyLiveActivityAuthorization(result)
            // The permission row is the confirmation; inserting a transient
            // success section here would jump the layout on every sheet dismissal.
            notice = result == .undetermined ? "尚未完成实时活动授权，请先允许通知转发。" : nil
        } catch {
            guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
            // A failed sheet presentation gives us no reliable current decision.
            liveActivityPermission.failCheck()
            recordLiveActivityAuthorizationError(error, operation: "authorizationSheet")
            notice = "暂时无法打开实时活动授权，请到 iPhone 设置的配件页面检查“实时活动”。通知权限与实时活动权限需分别确认。"
        }
    }

    private func applyLiveActivityAuthorization(_ result: AccessoryAuthorizationResult, permissionRevision: Int? = nil) {
        let accepted: Bool
        switch result {
        case .allow: accepted = liveActivityPermission.confirm(.allowed, revision: permissionRevision)
        case .limited: accepted = liveActivityPermission.confirm(.limited, revision: permissionRevision)
        case .deny: accepted = liveActivityPermission.confirm(.denied, revision: permissionRevision)
        case .undetermined: accepted = liveActivityPermission.confirm(.undetermined, revision: permissionRevision)
        @unknown default: accepted = liveActivityPermission.failCheck(revision: permissionRevision)
        }
        guard accepted else { return }
        saveConfirmedPermissions()
        #if DEBUG
        UserDefaults.standard.removeObject(forKey: "interop.debug.liveActivityError")
        UserDefaults.standard.removeObject(forKey: "interop.debug.liveActivityErrorOperation")
        UserDefaults.standard.set(liveActivityAuthorization.title, forKey: "interop.debug.liveActivityAuthorization")
        #endif
    }

    /// Domain and numeric code are enough to investigate platform failures.
    /// Never persist userInfo, localized descriptions, accessory IDs or content.
    private func recordLiveActivityAuthorizationError(_ error: any Error, operation: String) {
        let systemError = error as NSError
        let detail = "\(systemError.domain) / \(systemError.code)"
        technicalDetail = detail
        logger.error("Live Activity authorization \(operation, privacy: .public) failed: \(detail, privacy: .public)")
        #if DEBUG
        UserDefaults.standard.set(detail, forKey: "interop.debug.liveActivityError")
        UserDefaults.standard.set(operation, forKey: "interop.debug.liveActivityErrorOperation")
        UserDefaults.standard.set(liveActivityAuthorization.title, forKey: "interop.debug.liveActivityAuthorization")
        #endif
    }
}
