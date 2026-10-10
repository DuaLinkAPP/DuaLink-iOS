// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationLabCore

@Test func transportRecoveryIsBoundedAndResetsOnlyAfterDelivery() {
    var policy = LabReconnectPolicy()
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == false)
    policy.didDeliverFrame()
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.attempts == 1)
}

@Test func reconnectNeverReplaysPartiallyWrittenOrInFlightFrames() {
    var policy = LabReconnectPolicy()
    #expect(policy.beginRecovery(writeOffsets: [100], waitingForWrite: false) == false)
    #expect(policy.beginRecovery(writeOffsets: [0, 100], waitingForWrite: false) == false)
    #expect(policy.beginRecovery(writeOffsets: [0], waitingForWrite: true) == false)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: true) == false)
    #expect(policy.beginRecovery(writeOffsets: [-1], waitingForWrite: false) == false)
    #expect(policy.attempts == 0)
}

@Test func queuedFramesThatHaveNeverBeenWrittenCanSurviveRecovery() {
    var policy = LabReconnectPolicy()
    #expect(policy.beginRecovery(writeOffsets: [0, 0, 0], waitingForWrite: false) == true)
    #expect(policy.attempts == 1)
}

@Test func serviceRediscoveryAndLinkRecoveryShareTheBound() {
    var policy = LabReconnectPolicy()
    // A missing service followed by a disconnect cannot reset the retry budget.
    #expect(policy.beginRecovery(writeOffsets: [0], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [0], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == false)
}

@Test func incompleteProfileGetsOneLocalDisconnectAndReconnectAttempt() {
    var policy = LabReconnectPolicy()
    #expect(policy.beginProfileRecovery(writeOffsets: [0], waitingForWrite: false) == true)
    #expect(policy.waitingForProfileDisconnect)
    #expect(policy.attempts == 1)
    #expect(policy.beginProfileRecovery(writeOffsets: [0], waitingForWrite: false) == false)
    // Simulate didDisconnect: submission consumes the reserved attempt once.
    #expect(policy.beginRecovery(writeOffsets: [0], waitingForWrite: false) == true)
    #expect(!policy.waitingForProfileDisconnect)
    #expect(policy.attempts == 1)
    // An empty profile after reacquisition is terminal, not another hot loop.
    #expect(policy.beginProfileRecovery(writeOffsets: [0], waitingForWrite: false) == false)
    policy.didDeliverFrame()
    #expect(policy.beginProfileRecovery(writeOffsets: [], waitingForWrite: false) == true)
}

@Test func profileRecoveryUsesTheRemainingBudgetWithoutDoubleCharging() {
    var policy = LabReconnectPolicy()
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.beginProfileRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.attempts == 3)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == true)
    #expect(policy.attempts == 3)
    #expect(policy.beginRecovery(writeOffsets: [], waitingForWrite: false) == false)
}

@Test func profileRecoveryNeverCancelsOrReplaysPartiallySentFrames() {
    var policy = LabReconnectPolicy()
    #expect(policy.beginProfileRecovery(writeOffsets: [100], waitingForWrite: false) == false)
    #expect(policy.beginProfileRecovery(writeOffsets: [0], waitingForWrite: true) == false)
    #expect(!policy.waitingForProfileDisconnect)
    #expect(policy.attempts == 0)
}

@Test func cachedPendingConnectionAndFreshAdvertisementSubmitOnlyOnce() {
    let target = UUID()
    var policy = LabApprovedTargetPolicy(approvedID: target)
    let first = policy.submitConnection(to: target)
    let seen = policy.observeAdvertisement(from: target)
    let second = policy.submitConnection(to: target)
    #expect(first)
    #expect(seen)
    #expect(!second)
    #expect(policy.advertisementSeen)
    #expect(policy.connectSubmitted)
    #expect(!policy.connectionConfirmed)
}

@Test func emptyRetrievalCanWaitForItsFirstAuthorizedAdvertisement() {
    let target = UUID()
    var policy = LabApprovedTargetPolicy(approvedID: target)
    #expect(!policy.connectSubmitted)
    let seen = policy.observeAdvertisement(from: target)
    let submitted = policy.submitConnection(to: target)
    #expect(seen && submitted)
    #expect(!policy.connectionConfirmed)
}

@Test func anotherPeerCannotReplaceTheASKApprovedTarget() {
    let target = UUID()
    let other = UUID()
    var policy = LabApprovedTargetPolicy(approvedID: target)
    let seen = policy.observeAdvertisement(from: other)
    let submitted = policy.submitConnection(to: other)
    let connected = policy.confirmConnection(to: other)
    #expect(!seen && !submitted && !connected)
    #expect(!policy.advertisementSeen)
    #expect(!policy.connectSubmitted)
    #expect(!policy.connectionConfirmed)
}

@Test func restoredConnectedTargetNeverGetsAnotherConnectFromDiscovery() {
    let target = UUID()
    var policy = LabApprovedTargetPolicy(approvedID: target)
    let restored = policy.confirmConnection(to: target)
    let seen = policy.observeAdvertisement(from: target)
    let submitted = policy.submitConnection(to: target)
    #expect(restored && seen)
    #expect(!submitted)
    #expect(policy.connectionConfirmed)
}

@Test func targetFingerprintIsComparableAcrossClientsWithoutLoggingTheIdentifier() {
    let target = UUID()
    let fingerprint = LabApprovedTargetPolicy.fingerprint(target)
    #expect(fingerprint == LabApprovedTargetPolicy.fingerprint(target))
    #expect(fingerprint != LabApprovedTargetPolicy.fingerprint(UUID()))
    #expect(fingerprint.count == 16)
    #expect(fingerprint != target.uuidString)
    #expect(fingerprint.allSatisfy { $0.isHexDigit })
}
