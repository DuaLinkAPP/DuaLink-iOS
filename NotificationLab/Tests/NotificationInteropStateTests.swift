// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationInteropProductCore

@Test func unreadableOrDeniedAuthorizationNeverClaimsForwardingIsAllowed() {
    for state in [NotificationInteropAuthorization.unknown, .checking, .denied, .undetermined, .failed, .unavailable] {
        #expect(!state.permitsForwarding)
    }
    #expect(NotificationInteropAuthorization.limited.permitsForwarding)
    #expect(!NotificationInteropAuthorization.allowed.title.contains("已连接"))
}

@Test func deniedPermissionRequiresSystemSettingsInsteadOfFakeLocalToggle() {
    #expect(NotificationInteropAuthorization.denied.primaryAction == "管理通知权限")
    #expect(NotificationInteropAuthorization.limited.primaryAction == "管理通知权限")
    #expect(NotificationInteropAuthorization.failed.primaryAction == "重新检查")
}

@Test func deviceNamePrefersActualBroadcastAndRejectsOldExperimentLabels() {
    #expect(NotificationAccessoryName.display(advertised: "示例用户的鸿蒙手机", discovered: "鸿蒙手机") == "示例用户的鸿蒙手机")
    #expect(NotificationAccessoryName.display(advertised: nil, discovered: "DuaLink 通知实验设备") == "鸿蒙手机")
    #expect(NotificationAccessoryName.display(advertised: "  \n", discovered: "HUAWEI Pura 80") == "HUAWEI Pura 80")
    #expect(NotificationAccessoryName.display(advertised: "华为\n手机", discovered: nil) == "华为手机")
}

@Test func silentRefreshPreservesConfirmedPermissionWithoutReplacingItWithLoading() {
    var state = NotificationPermissionState()
    state.confirm(.allowed)
    state.beginCheck()
    #expect(state.isChecking)
    #expect(state.confirmed == .allowed)
    #expect(state.currentlyPermitted)
    #expect(state.historicalSummary == nil)
}

@Test func readFailureDoesNotDowngradePermissionJustConfirmedInTheSystemSheet() {
    var state = NotificationPermissionState()
    state.confirm(.allowed)
    let request = state.beginCheck()
    state.failCheck(revision: request)
    #expect(state.confirmed == .allowed)
    #expect(state.historicalSummary == nil)
    #expect(state.currentlyPermitted)
    #expect(!state.needsReconfirmation)
    #expect(state.queryFailed)
}

@Test func readFailureCannotPromoteRestoredPermissionIntoAFreshGrant() {
    var state = NotificationPermissionState()
    state.restore(.allowed)
    let request = state.beginCheck()
    state.failCheck(revision: request)
    #expect(state.confirmed == .allowed)
    #expect(state.historicalSummary == "上次已允许，暂未重新确认")
    #expect(!state.currentlyPermitted)
    #expect(state.needsReconfirmation)
    #expect(state.queryFailed)
}

@Test func invalidatedSessionRequiresReconfirmationEvenIfNextQueryFails() {
    var state = NotificationPermissionState()
    state.confirm(.allowed)
    state.requireReconfirmation()
    let request = state.beginCheck()
    state.failCheck(revision: request)
    #expect(state.confirmed == .allowed)
    #expect(!state.currentlyPermitted)
    #expect(state.needsReconfirmation)
}

@Test func firstReadFailureNeverInventsAPreviousGrantOrDenial() {
    var state = NotificationPermissionState()
    state.beginCheck()
    state.failCheck()
    #expect(state.confirmed == nil)
    #expect(state.historicalSummary == nil)
    #expect(!state.currentlyPermitted)
}

@Test func realDenialImmediatelyReplacesPreviouslyAllowedPermission() {
    var state = NotificationPermissionState()
    state.confirm(.allowed)
    state.failCheck()
    let request = state.beginCheck()
    let accepted = state.confirm(.denied, revision: request)
    #expect(accepted)
    #expect(state.confirmed == .denied)
    #expect(state.currentlyConfirmed)
    #expect(!state.currentlyPermitted)
    #expect(!state.queryFailed)
    #expect(state.historicalSummary == nil)
}

@Test func lateQueryCannotOverwriteTheUsersNewSheetSelection() {
    var state = NotificationPermissionState()
    let olderQuery = state.beginCheck()
    state.cancelCheck()
    state.confirm(.allowed) // User confirmed in the system authorization sheet.
    let acceptedStaleDecision = state.confirm(.denied, revision: olderQuery)
    let acceptedStaleFailure = state.failCheck(revision: olderQuery)
    #expect(!acceptedStaleDecision)
    #expect(!acceptedStaleFailure)
    #expect(state.confirmed == .allowed)
    #expect(state.currentlyPermitted)
}

@Test func cachedPermissionIsHistoricalAndScopedToItsPhysicalDevice() throws {
    let phone = UUID()
    let otherPhone = UUID()
    let record = NotificationPermissionMemory(deviceID: phone, notifications: .allowed, liveActivities: .limited)
    let loaded = try JSONDecoder().decode(NotificationPermissionMemory.self, from: JSONEncoder().encode(record))
    #expect(loaded.forDevice(phone)?.liveActivities == .limited)
    #expect(loaded.forDevice(otherPhone) == nil)
    #expect(loaded.forDevice(nil) == nil)
    var state = NotificationPermissionState()
    state.restore(loaded.forDevice(phone)?.liveActivities)
    #expect(state.confirmed == .limited)
    #expect(!state.currentlyPermitted)
    #expect(state.needsReconfirmation)
    state.restore(loaded.forDevice(otherPhone)?.liveActivities)
    #expect(state.confirmed == nil)
    #expect(!state.needsReconfirmation)
}

@Test func deviceRemovalRejectsAnOlderReadEvenWhenNewRequestStarts() {
    var state = NotificationPermissionState()
    let oldRequest = state.beginCheck()
    state.restore(nil)
    let newRequest = state.beginCheck()
    let acceptedOldRequest = state.confirm(.allowed, revision: oldRequest)
    let acceptedNewRequest = state.confirm(.denied, revision: newRequest)
    #expect(!acceptedOldRequest)
    #expect(acceptedNewRequest)
}

@Test func failedReadWithUndeterminedPermissionOpensSettingsAndLabelsTheSameAction() {
    var state = NotificationPermissionState()
    state.confirm(.undetermined)
    state.failCheck()
    let action = NotificationPermissionEntryAction.resolve(state: state, unsupportedAccessory: false, unavailable: false)
    #expect(action == .manageSettings)
    #expect(action.title == "管理通知权限")
}

@Test func unsupportedAccessoryDoesNotRepeatRequestAfterAQuietUndeterminedRead() {
    var state = NotificationPermissionState()
    state.confirm(.undetermined)
    let action = NotificationPermissionEntryAction.resolve(state: state, unsupportedAccessory: true, unavailable: false)
    #expect(action == .manageSettings)
    #expect(action.title == "管理通知权限")
}

@Test func freshUndeterminedPermissionRequestsForwardingAndLabelsTheSameAction() {
    var state = NotificationPermissionState()
    state.confirm(.undetermined)
    let action = NotificationPermissionEntryAction.resolve(state: state, unsupportedAccessory: false, unavailable: false)
    #expect(action == .requestForwarding)
    #expect(action.title == "允许通知转发")
}

@Test func deniedPermissionIsPreservedWhenChoosingItsSettingsAction() {
    var state = NotificationPermissionState()
    state.confirm(.denied)
    let action = NotificationPermissionEntryAction.resolve(state: state, unsupportedAccessory: false, unavailable: false)
    #expect(action == .manageSettings)
    #expect(action.title == "管理通知权限")
    #expect(state.confirmed == .denied)
    #expect(!state.currentlyPermitted)
}
