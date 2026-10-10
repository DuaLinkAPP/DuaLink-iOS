// SPDX-License-Identifier: MPL-2.0
import AccessoryNotifications
import AccessorySetupKit
import Observation
import OSLog
import UIKit

/// UI owns setup and consent only. iOS owns the three background extensions;
/// this model never disconnects the existing phone/SMS BLE manager.
@available(iOS 26.5, *)
@MainActor @Observable
final class NotificationInteropModel {
    var messageMode = InteropModeStore.product.read().mode
    var accessories: [ASAccessory] = []
    var deviceNames = UserDefaults.standard.dictionary(forKey: "interop.deviceNames") as? [String: String] ?? [:]
    var notificationPermission = NotificationPermissionState()
    var liveActivityPermission = NotificationPermissionState()
    var notificationUnavailable = false
    var notificationUnsupportedAccessory = false
    var permissionDeviceID: UUID?
    var permissionAccessorySnapshot: LabAccessoryAuthorizationRecord?
    var permissionAction: PermissionAction?
    enum PermissionAction { case notifications, liveActivities }
    var ready = false
    var busy = false
    var notice: String?
    var lastChecked: Date?
    var technicalDetail = ""
    var session: ASAccessorySession?
    var generation = 0
    var authorizationRevision = 0
    var checkID = UUID()
    var checkTask: Task<Void, Never>?
    var refreshPending = false
    var renameAttempt: UUID?
    @ObservationIgnored var renameTimeout: Task<Void, Never>?
    var reconnecting = false
    var reconnectOwnsBusy = false
    var automaticConnectionPolicy = NotificationAutoConnectPolicy()
    var reconnectMode: NotificationReconnectMode = .notificationService
    var reconnectRevision = 0
    var connectionNotice: String?
    @ObservationIgnored let reconnectController = NotificationReconnectController()
    let logger = Logger(subsystem: "ESP.DuaLink", category: "notification-interop")

    var accessory: ASAccessory? { accessories.count == 1 ? accessories.first : nil }
    var canManage: Bool { notificationModeEnabled && ready && !busy && accessory?.state == .authorized }

    func start() {
        guard notificationModeEnabled else { return }
        guard session == nil else { refresh(); return }
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            notificationUnavailable = true
            notice = "通知互联需要在 iPhone 上使用。"
            return
        }
        #if targetEnvironment(simulator)
        notice = "模拟器可预览界面，连接和转发需要 iPhone 真机。"
        #else
        generation += 1
        let revision = generation
        let activeSession = ASAccessorySession()
        session = activeSession
        activeSession.activate(on: .main) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.generation == revision, let activeSession = self.session else { return }
                if event.eventType == .pickerSetupRename {
                    self.renameTimeout?.cancel()
                }
                if event.eventType == .invalidated {
                    self.finishRenameLease()
                    self.stopReconnect()
                    self.ready = false
                    self.generation += 1
                    self.authorizationRevision += 1
                    self.session = nil
                    self.cancelPermissionCheck()
                    self.busy = false
                    self.permissionAction = nil
                    self.notificationPermission.requireReconfirmation()
                    self.liveActivityPermission.requireReconfirmation()
                    self.notice = "设备管理暂时不可用，请点“重新检查”恢复。"
                    return
                }
                if let error = event.error {
                    if !self.ready {
                        self.generation += 1
                        self.session = nil
                        activeSession.invalidate()
                    }
                    self.report(error)
                    return
                }
                if event.eventType == .activated { self.ready = true }
                self.accessories = activeSession.accessories
                self.refreshDeviceNames()
                let authorizationBoundaryChanged = self.resolvePermissionDevice()
                if authorizationBoundaryChanged { self.stopReconnect() }
                // Only identity/authorization changes refresh permissions. Name
                // and connection telemetry for an unchanged scope stay quiet.
                if event.eventType == .activated || authorizationBoundaryChanged { self.refresh() }
                // Establish the ASK-approved GATT service even before forwarding
                // consent can be read. This never requests or changes consent.
                self.connectAutomaticallyIfEligible()
            }
        }
        #endif
    }

    func performPrimaryAction() async {
        guard let accessory else { addAccessory(); return }
        guard canManage else { return }
        switch notificationEntryAction {
        case .manageSettings: await managePermissions(accessory)
        case .requestForwarding: await requestPermission(accessory)
        }
    }

    func requestPermission(_ accessory: ASAccessory) async {
        await performAuthorization(accessory) {
            try await AccessoryNotificationCenter().requestForwarding(for: accessory)
        }
    }

    func managePermissions(_ accessory: ASAccessory) async {
        let sceneID = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive }?.session.persistentIdentifier
        await performAuthorization(accessory) {
            try await AccessoryNotificationCenter().presentSettings(for: accessory, scenePersistentIdentifier: sceneID)
        }
    }

    private func performAuthorization(_ accessory: ASAccessory,
        operation: () async throws -> ForwardingDecision) async {
        guard canManage else { return }
        stopAutomaticConnectionIfNeeded()
        cancelPermissionCheck()
        let revision = authorizationRevision
        let sessionGeneration = generation
        busy = true
        permissionAction = .notifications
        defer {
            if generation == sessionGeneration {
                busy = false
                permissionAction = nil
                refresh()
            }
        }
        do {
            let decision = try await operation()
            guard isCurrent(accessory, revision: revision) else { return }
            apply(decision)
        } catch {
            guard isCurrent(accessory, revision: revision) else { return }
            notificationPermission.failCheck()
            report(error)
        }
    }

    func isCurrent(_ accessory: ASAccessory, revision: Int) -> Bool {
        notificationModeEnabled && !Task.isCancelled && ready && authorizationRevision == revision &&
            accessory.bluetoothIdentifier != nil &&
            self.accessory?.bluetoothIdentifier == accessory.bluetoothIdentifier &&
            self.accessory?.state == .authorized
    }

    func apply(_ decision: ForwardingDecision, permissionRevision: Int? = nil) {
        let accepted: Bool
        switch decision {
        case .allow: accepted = notificationPermission.confirm(.allowed, revision: permissionRevision)
        case .limited: accepted = notificationPermission.confirm(.limited, revision: permissionRevision)
        case .deny: accepted = notificationPermission.confirm(.denied, revision: permissionRevision)
        case .undetermined: accepted = notificationPermission.confirm(.undetermined, revision: permissionRevision)
        @unknown default: accepted = notificationPermission.failCheck(revision: permissionRevision)
        }
        guard accepted else { return }
        notificationUnavailable = false
        // An undetermined status is not proof that requestForwarding now
        // accepts this registered accessory. Keep the explicit recovery route.
        if decision == .allow || decision == .limited || decision == .deny {
            notificationUnsupportedAccessory = false
        }
        saveConfirmedPermissions()
        if permissionRevision == nil { notice = nil }
        lastChecked = Date()
        #if DEBUG
        UserDefaults.standard.set(authorization.rawValue, forKey: "interop.debug.authorization")
        #endif
        refreshDeviceNames()
        technicalDetail = "通知授权：\(decision)"
    }

}
