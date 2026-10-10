// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationLabCore

@Test func sameAuthorizedIdentityDoesNotCreateANewPermissionBoundary() {
    let identifier = UUID()
    let previous = LabAccessoryAuthorizationRecord(identifier: identifier, authorized: true)
    let unchanged = LabAccessoryAuthorizationRecord(identifier: identifier, authorized: true)
    #expect(LabAccessoryAuthorizationPolicy.boundary(previous: previous, current: unchanged) == .unchanged)
    #expect(LabAccessoryAuthorizationPolicy.select([unchanged], boundID: identifier) == .keep)
}

@Test func revocationAndReauthorizationOfTheSameUUIDAreSeparateBoundaries() {
    let identifier = UUID()
    let allowed = LabAccessoryAuthorizationRecord(identifier: identifier, authorized: true)
    let revoked = LabAccessoryAuthorizationRecord(identifier: identifier, authorized: false)
    #expect(LabAccessoryAuthorizationPolicy.boundary(previous: allowed, current: revoked) == .authorizationChanged)
    #expect(LabAccessoryAuthorizationPolicy.boundary(previous: revoked, current: revoked) == .unchanged)
    #expect(LabAccessoryAuthorizationPolicy.boundary(previous: revoked, current: allowed) == .authorizationChanged)
    #expect(LabAccessoryAuthorizationPolicy.select([revoked], boundID: identifier) == .reject)
}

@Test func changedOrRemovedApprovedPeerTerminatesInsteadOfSwitchingRecipients() {
    let old = UUID()
    let replacement = LabAccessoryAuthorizationRecord(identifier: UUID(), authorized: true)
    let previous = LabAccessoryAuthorizationRecord(identifier: old, authorized: true)
    #expect(LabAccessoryAuthorizationPolicy.boundary(previous: previous, current: replacement) == .identityChanged)
    #expect(LabAccessoryAuthorizationPolicy.select([replacement], boundID: old) == .reject)
    #expect(LabAccessoryAuthorizationPolicy.select([], boundID: old) == .reject)
}

@Test func unrelatedUnauthorizedRecordDoesNotTearDownTheBoundPeer() {
    let identifier = UUID()
    let target = LabAccessoryAuthorizationRecord(identifier: identifier, authorized: true)
    let unrelated = LabAccessoryAuthorizationRecord(identifier: UUID(), authorized: false)
    #expect(LabAccessoryAuthorizationPolicy.select([target, unrelated], boundID: identifier) == .keep)
    // Removing only the unrelated record must remain a no-op for this connection.
    #expect(LabAccessoryAuthorizationPolicy.select([target], boundID: identifier) == .keep)
}

@Test func extensionBindsOnlyOneIdentifiedAuthorizedAccessory() {
    let identifier = UUID()
    let target = LabAccessoryAuthorizationRecord(identifier: identifier, authorized: true)
    let unidentified = LabAccessoryAuthorizationRecord(identifier: nil, authorized: true)
    let other = LabAccessoryAuthorizationRecord(identifier: UUID(), authorized: true)
    #expect(LabAccessoryAuthorizationPolicy.select([target], boundID: nil) == .bind(identifier))
    #expect(LabAccessoryAuthorizationPolicy.select([unidentified], boundID: nil) == .reject)
    #expect(LabAccessoryAuthorizationPolicy.select([target, other], boundID: identifier) == .reject)
}
