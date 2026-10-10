// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import NotificationLabCore

@Test func restoredDataSubscriptionRefreshesOnlyOncePerConnection() {
    var state = LabSubscriptionState()
    #expect(state.prepare(isData: true, isNotifying: true) == .disable)
    #expect(state.observed(isNotifying: true) == .none)
    #expect(state.observed(isNotifying: false) == .enable)
    #expect(state.observed(isNotifying: false) == .none)
    #expect(!state.isReady)
    #expect(state.observed(isNotifying: true) == .ready)
    #expect(state.isReady)
    // Repeated discovery or a new send batch must not reopen the handshake.
    #expect(state.prepare(isData: true, isNotifying: true) == .none)
    #expect(state.isReady)
    state.reset()
    #expect(state.prepare(isData: true, isNotifying: true) == .disable)
}

@Test func freshDataSubscriptionWaitsForAcknowledgement() {
    var state = LabSubscriptionState()
    #expect(state.prepare(isData: true, isNotifying: false) == .enable)
    #expect(!state.isReady)
    #expect(state.prepare(isData: true, isNotifying: true) == .none)
    #expect(state.observed(isNotifying: true) == .ready)
}

@Test(arguments: [true, false]) func securityNeverForcesAnUnsubscribe(isNotifying: Bool) {
    var state = LabSubscriptionState()
    #expect(state.prepare(isData: false, isNotifying: isNotifying) == .enable)
    #expect(state.observed(isNotifying: true) == .ready)
}

@Test func duplicateSubscriptionSuccessDoesNotEmitReadyAgain() {
    var state = LabSubscriptionState()
    _ = state.prepare(isData: true, isNotifying: false)
    #expect(state.observed(isNotifying: true) == .ready)
    // Only .ready cancels the setup deadline. Returning .none preserves any
    // subsequent write's timeout when CoreBluetooth repeats its notification.
    #expect(state.observed(isNotifying: true) == .none)
    #expect(state.observed(isNotifying: false) == .lost)
}

@Test func lateSubscriptionCallbackCannotReadyAResetSession() {
    var state = LabSubscriptionState()
    _ = state.prepare(isData: true, isNotifying: false)
    state.reset()
    #expect(state.observed(isNotifying: true) == .none)
    #expect(!state.isReady)
}

@Test func idleDataBatchReadsRemoteStateBeforeSending() {
    var probe = LabSubscriptionProbe()
    let began = probe.begin(isData: true, ready: true, queueEmpty: true, writing: false)
    #expect(began)
    #expect(probe.pending)
    let duplicate = probe.begin(isData: true, ready: true, queueEmpty: true, writing: false)
    #expect(!duplicate)
    let state = probe.complete(1)
    #expect(state == .subscribed)
    #expect(!probe.pending)
}

@Test func remoteUnsubscribeRequiresOneRenewalAndResetRejectsStaleRead() {
    var probe = LabSubscriptionProbe()
    _ = probe.begin(isData: true, ready: true, queueEmpty: true, writing: false)
    let state = probe.complete(0)
    #expect(state == .renew)
    probe.reset()
    let stale = probe.complete(1)
    #expect(stale == .invalid)
}

@Test func probeDoesNotInterruptSecurityOrWrites() {
    for (data, ready, empty, writing) in [(false, true, true, false), (true, false, true, false),
                                         (true, true, false, false), (true, true, true, true)] {
        var probe = LabSubscriptionProbe()
        let started = probe.begin(isData: data, ready: ready, queueEmpty: empty, writing: writing)
        #expect(!started)
    }
}

@Test(arguments: [2, 3]) func remoteIndicationAlsoProvesSubscription(value: Int) {
    var probe = LabSubscriptionProbe()
    _ = probe.begin(isData: true, ready: true, queueEmpty: true, writing: false)
    let result = probe.complete(value)
    #expect(result == .subscribed)
}
