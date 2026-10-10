// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Authorization is not proof of a live BLE connection or of message delivery.
nonisolated enum NotificationInteropAuthorization: String, Sendable {
    case unknown, checking, allowed, limited, denied, undetermined, unavailable, failed

    var title: String {
        switch self {
        case .unknown: "尚未检查通知权限"
        case .checking: "正在检查通知权限"
        case .allowed: "已允许通知转发"
        case .limited: "已允许部分 App 通知"
        case .denied: "通知转发未开启"
        case .undetermined: "等待允许通知转发"
        case .unavailable: "当前无法使用通知互联"
        case .failed: "暂时无法读取通知权限"
        }
    }

    var permitsForwarding: Bool { self == .allowed || self == .limited }
    var primaryAction: String {
        switch self {
        case .allowed, .limited, .denied: "管理通知权限"
        case .undetermined, .unknown: "允许通知转发"
        case .checking: "正在检查…"
        case .failed, .unavailable: "重新检查"
        }
    }
}

/// Only decisions actually returned by the system can enter the permission cache.
nonisolated enum NotificationForwardingDecision: String, Codable, Sendable {
    case allowed, limited, denied, undetermined

    var permitsForwarding: Bool { self == .allowed || self == .limited }
}

/// A failed query is uncertainty, never a replacement for the last system decision.
nonisolated struct NotificationPermissionState: Equatable, Sendable {
    private(set) var confirmed: NotificationForwardingDecision?
    private(set) var isChecking = false
    private(set) var queryFailed = false
    private(set) var needsReconfirmation = false
    private(set) var revision = 0

    var currentlyConfirmed: Bool { confirmed != nil && !needsReconfirmation }
    var currentlyPermitted: Bool { currentlyConfirmed && confirmed?.permitsForwarding == true }

    var historicalSummary: String? {
        guard needsReconfirmation, let confirmed else { return nil }
        switch confirmed {
        case .allowed: return "上次已允许，暂未重新确认"
        case .limited: return "上次允许部分 App，暂未重新确认"
        case .denied: return "上次未开启，暂未重新确认"
        case .undetermined: return "尚未确认当前授权"
        }
    }

    @discardableResult
    mutating func beginCheck() -> Int {
        revision += 1
        isChecking = true
        return revision
    }
    mutating func cancelCheck() { revision += 1; isChecking = false }
    @discardableResult
    mutating func confirm(_ decision: NotificationForwardingDecision, revision expected: Int? = nil) -> Bool {
        guard expected == nil || expected == revision else { return false }
        revision += 1
        confirmed = decision
        isChecking = false
        queryFailed = false
        needsReconfirmation = false
        return true
    }
    @discardableResult
    mutating func failCheck(revision expected: Int? = nil) -> Bool {
        guard expected == nil || expected == revision else { return false }
        revision += 1
        isChecking = false
        queryFailed = true
        // A read failure cannot revoke a decision confirmed in this session.
        // Only restored memory or an invalidated session needs reconfirmation.
        return true
    }
    mutating func restore(_ decision: NotificationForwardingDecision?) {
        let nextRevision = revision + 1
        self = Self()
        revision = nextRevision
        confirmed = decision
        needsReconfirmation = decision != nil
    }
    mutating func requireReconfirmation() {
        cancelCheck()
        needsReconfirmation = confirmed != nil
    }
}

/// One saved physical device. Device changes cannot inherit its authorization.
nonisolated struct NotificationPermissionMemory: Codable, Equatable, Sendable {
    let deviceID: UUID
    var notifications: NotificationForwardingDecision?
    var liveActivities: NotificationForwardingDecision?

    func forDevice(_ identifier: UUID?) -> Self? {
        identifier == deviceID ? self : nil
    }
}

/// One decision drives both the button title and the API call. A failed status
/// read on a registered accessory must not send the user into a request loop.
nonisolated enum NotificationPermissionEntryAction: Equatable, Sendable {
    case requestForwarding, manageSettings

    var title: String {
        switch self {
        case .requestForwarding: "允许通知转发"
        case .manageSettings: "管理通知权限"
        }
    }

    static func resolve(state: NotificationPermissionState, unsupportedAccessory: Bool,
                        unavailable: Bool) -> Self {
        if state.queryFailed || state.isChecking || unsupportedAccessory || unavailable {
            return .manageSettings
        }
        switch state.confirmed {
        case .allowed, .limited, .denied: return .manageSettings
        case .undetermined, nil: return .requestForwarding
        }
    }
}
