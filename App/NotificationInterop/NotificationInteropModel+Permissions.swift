// SPDX-License-Identifier: MPL-2.0
import AccessoryNotifications
import AccessorySetupKit
import Foundation
import OSLog

@available(iOS 26.5, *)
extension NotificationInteropModel {
    private static let permissionMemoryKey = "interop.lastConfirmedPermissions.v1"

    var authorization: NotificationInteropAuthorization {
        if let decision = notificationPermission.confirmed {
            switch decision {
            case .allowed: return .allowed
            case .limited: return .limited
            case .denied: return .denied
            case .undetermined: return .undetermined
            }
        }
        if notificationUnavailable { return .unavailable }
        if notificationPermission.queryFailed { return .failed }
        return notificationPermission.isChecking ? .checking : .unknown
    }

    var notificationPermissionTitle: String {
        notificationPermission.historicalSummary ?? authorization.title
    }

    var notificationEntryAction: NotificationPermissionEntryAction {
        NotificationPermissionEntryAction.resolve(state: notificationPermission,
            unsupportedAccessory: notificationUnsupportedAccessory,
            unavailable: notificationUnavailable)
    }

    var notificationPrimaryAction: String { notificationEntryAction.title }

    /// Coalesce appearance/foreground events into one quiet read. An existing
    /// read already covers duplicate triggers; it must not enqueue itself again.
    func refresh() {
        guard notificationModeEnabled, checkTask == nil else { return }
        refreshPending = true
        drainRefresh()
    }

    func drainRefresh() {
        guard notificationModeEnabled, ready, !busy, checkTask == nil, refreshPending,
              let accessory, accessory.state == .authorized else { return }
        refreshPending = false
        let identifier = UUID()
        checkID = identifier
        checkTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self, self.checkID == identifier, !Task.isCancelled else { return }
            await self.check(accessory)
            guard self.checkID == identifier else { return }
            self.checkTask = nil
            if self.refreshPending { self.drainRefresh() }
            // Run after clearing checkTask, never from apply/check itself: an
            // automatic attempt must not cancel the query that scheduled it.
            self.connectAutomaticallyIfEligible()
        }
    }

    func check(_ accessory: ASAccessory) async {
        guard ready, !busy, accessory.state == .authorized else { return }
        let revision = authorizationRevision
        let sessionGeneration = generation
        let permissionRevision = notificationPermission.beginCheck()
        do {
            let decision = try await AccessoryNotificationCenter().forwardingStatus(for: accessory)
            guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
            apply(decision, permissionRevision: permissionRevision)
        } catch {
            guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
            notificationPermission.failCheck(revision: permissionRevision)
            recordNotificationError(error, operation: "query")
            if let typed = error as? AccessoryError, typed == .unsupportedAccessory {
                notificationUnsupportedAccessory = true
            }
            // Quiet status-read failures never become consent denial or a setup alert.
            #if DEBUG
            UserDefaults.standard.set(technicalDetail, forKey: "interop.debug.notificationQueryError")
            #endif
        }
        guard generation == sessionGeneration, isCurrent(accessory, revision: revision) else { return }
        await checkLiveActivityAuthorization(accessory, revision: revision, sessionGeneration: sessionGeneration)
    }

    /// User operations supersede silent reads even when the SDK ignores task
    /// cancellation. Both model and per-permission revisions reject late results.
    func cancelPermissionCheck() {
        authorizationRevision += 1
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        refreshPending = false
        notificationPermission.cancelCheck()
        liveActivityPermission.cancelCheck()
    }

    /// Call after reading the ASK accessory list, never after a connection event
    /// alone. Cached decisions are restored only for the same physical device.
    @discardableResult
    func resolvePermissionDevice() -> Bool {
        let identifier = accessory?.bluetoothIdentifier
        let current = LabAccessoryAuthorizationRecord(identifier: identifier,
                                                       authorized: accessory?.state == .authorized)
        let boundary = LabAccessoryAuthorizationPolicy.boundary(previous: permissionAccessorySnapshot, current: current)
        guard boundary != .unchanged else { return false }
        permissionAccessorySnapshot = current
        cancelPermissionCheck()
        permissionDeviceID = identifier
        notificationUnavailable = false
        notificationUnsupportedAccessory = false
        lastChecked = nil
        if boundary == .authorizationChanged {
            // Retain same-device history, but a re-pair/revocation invalidates
            // both in-flight results and any claim of freshly confirmed consent.
            notificationPermission.requireReconfirmation()
            liveActivityPermission.requireReconfirmation()
            return true
        }
        notificationPermission.restore(nil)
        liveActivityPermission.restore(nil)
        guard let identifier else {
            UserDefaults.standard.removeObject(forKey: Self.permissionMemoryKey)
            return true
        }
        if let data = UserDefaults.standard.data(forKey: Self.permissionMemoryKey), data.count < 1024,
           let memory = try? JSONDecoder().decode(NotificationPermissionMemory.self, from: data),
           let matching = memory.forDevice(identifier) {
            notificationPermission.restore(matching.notifications)
            liveActivityPermission.restore(matching.liveActivities)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.permissionMemoryKey)
        }
        return true
    }

    func saveConfirmedPermissions() {
        guard let identifier = permissionDeviceID,
              identifier == accessory?.bluetoothIdentifier else { return }
        let memory = NotificationPermissionMemory(deviceID: identifier,
            notifications: notificationPermission.confirmed,
            liveActivities: liveActivityPermission.confirmed)
        if let data = try? JSONEncoder().encode(memory) {
            UserDefaults.standard.set(data, forKey: Self.permissionMemoryKey)
        }
    }
}
