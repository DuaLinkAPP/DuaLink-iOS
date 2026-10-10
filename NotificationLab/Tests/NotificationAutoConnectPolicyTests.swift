// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationInteropProductCore

@Test func foregroundVisitPermitsOnlyOneAutomaticAttemptForEachTarget() {
    let target = UUID()
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    let first = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    let afterCompletionRefresh = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    policy.activateScene() // Repeated active notification is not a new visit.
    let repeatedActive = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    #expect(first)
    #expect(!afterCompletionRefresh && !repeatedActive)
}

@Test func inactivePermissionSheetCannotResetAutomaticAttemptBudget() {
    let target = UUID()
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    _ = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    policy.deactivateScene()
    let inactiveAttempt = policy.claimAttempt(for: UUID(), permissionDeviceID: nil, accessoryAuthorized: true)
    policy.activateScene()
    let afterSheet = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    #expect(!inactiveAttempt && !afterSheet)
}

@Test func realBackgroundAndNextForegroundPermitOneFreshAttempt() {
    let target = UUID()
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    _ = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    policy.enterBackground()
    let whileBackground = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    policy.activateScene()
    let afterReturn = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    let duplicate = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    #expect(!whileBackground)
    #expect(afterReturn && !duplicate)
}

@Test func hiddenPageCannotConnectEvenIfSceneBecomesActive() {
    let target = UUID()
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    _ = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    policy.hidePage()
    policy.activateScene()
    let hiddenAttempt = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    policy.showPage(sceneActive: true)
    let reopened = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    #expect(!hiddenAttempt && reopened)
}

@Test func unapprovedAndAnotherDevicesScopeNeverTriggerAutomaticConnect() {
    let target = UUID()
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    let denied = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: false)
    let unsupported = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: false)
    let wrongCache = policy.claimAttempt(for: target, permissionDeviceID: UUID(), accessoryAuthorized: true)
    let noResolvedDevice = policy.claimAttempt(for: target, permissionDeviceID: nil, accessoryAuthorized: true)
    let laterAllowed = policy.claimAttempt(for: target, permissionDeviceID: target, accessoryAuthorized: true)
    #expect(!denied && !unsupported && !wrongCache && !noResolvedDevice)
    #expect(laterAllowed)
}

@Test func registeredDeviceConnectsBeforeForwardingConsentWithoutClaimingAuthorization() {
    let target = UUID()
    var permission = NotificationPermissionState()
    permission.restore(nil)
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    let attempt = policy.claimAttempt(for: target, permissionDeviceID: target,
        accessoryAuthorized: true)
    #expect(attempt)
    #expect(!permission.currentlyPermitted)
    #expect(permission.confirmed == nil)
}

@Test func switchingTargetsDoesNotGiveTheFirstTargetAnotherAutomaticAttempt() {
    let firstTarget = UUID()
    let secondTarget = UUID()
    var policy = NotificationAutoConnectPolicy()
    policy.showPage(sceneActive: true)
    let first = policy.claimAttempt(for: firstTarget, permissionDeviceID: firstTarget, accessoryAuthorized: true)
    let second = policy.claimAttempt(for: secondTarget, permissionDeviceID: secondTarget, accessoryAuthorized: true)
    let firstAgain = policy.claimAttempt(for: firstTarget, permissionDeviceID: firstTarget, accessoryAuthorized: true)
    #expect(first && second && !firstAgain)
}
