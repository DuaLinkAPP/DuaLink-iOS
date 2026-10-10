// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
import CoreBluetooth

@available(iOS 26.5, *)
extension NotificationInteropModel {
    func notificationPageAppeared(sceneActive: Bool) {
        automaticConnectionPolicy.showPage(sceneActive: sceneActive)
        start()
        connectAutomaticallyIfEligible()
    }

    func notificationSceneBecameActive() {
        automaticConnectionPolicy.activateScene()
        start()
        connectAutomaticallyIfEligible()
    }

    func notificationSceneBecameInactive() {
        // Permission sheets produce inactive/active without leaving this visit.
        automaticConnectionPolicy.deactivateScene()
    }

    func notificationSceneEnteredBackground() {
        automaticConnectionPolicy.enterBackground()
        stopReconnect()
    }

    func notificationPageDisappeared() {
        automaticConnectionPolicy.hidePage()
        stopReconnect()
    }

    func connectAutomaticallyIfEligible() {
        guard notificationModeEnabled, ready, !busy, !reconnecting,
              let accessory, accessory.state == .authorized,
              let identifier = accessory.bluetoothIdentifier else { return }
        if reconnectController.target == identifier,
           reconnectController.peripheral?.state == .connected,
           reconnectController.completion == nil { return }
        guard automaticConnectionPolicy.claimAttempt(for: identifier,
            permissionDeviceID: permissionDeviceID,
            accessoryAuthorized: accessory.state == .authorized) else { return }
        // Eligibility was consumed before submission. Completion refreshes and
        // duplicate foreground events cannot cause a retry loop.
        checkConnection(mode: .notificationService, automatic: true)
    }

    func stopAutomaticConnectionIfNeeded() {
        if reconnecting && !reconnectOwnsBusy { stopReconnect() }
    }
}
