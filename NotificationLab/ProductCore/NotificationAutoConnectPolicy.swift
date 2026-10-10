// SPDX-License-Identifier: MPL-2.0
import Foundation

/// One automatic attempt per visible foreground visit and physical accessory.
/// Inactive system sheets pause eligibility without granting a new attempt.
/// ASK authorization permits a basic GATT connection. Forwarding consent is
/// checked separately and must not prevent onboarding from reaching the service.
nonisolated struct NotificationAutoConnectPolicy: Sendable {
    private(set) var pageVisible = false
    private(set) var sceneActive = false
    private var attemptedTargets: Set<UUID> = []

    mutating func showPage(sceneActive: Bool) {
        if !pageVisible { attemptedTargets.removeAll() }
        pageVisible = true
        self.sceneActive = sceneActive
    }

    mutating func activateScene() { sceneActive = true }
    mutating func deactivateScene() { sceneActive = false }

    mutating func enterBackground() {
        sceneActive = false
        attemptedTargets.removeAll()
    }

    mutating func hidePage() {
        pageVisible = false
        sceneActive = false
        attemptedTargets.removeAll()
    }

    mutating func claimAttempt(for identifier: UUID, permissionDeviceID: UUID?,
                               accessoryAuthorized: Bool) -> Bool {
        guard pageVisible, sceneActive, identifier == permissionDeviceID,
              accessoryAuthorized,
              !attemptedTargets.contains(identifier) else { return false }
        attemptedTargets.insert(identifier)
        return true
    }
}
