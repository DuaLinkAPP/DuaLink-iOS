// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import NotificationInteropProductCore

@Test @MainActor func setupLeaseResumesEachIdleOwnerOnce() {
    let lease = NotificationSetupLease()
    var events: [String] = []
    lease.register("a", pause: { events.append("pause-a"); return true }, resume: { events.append("resume-a") })
    lease.register("b", pause: { events.append("pause-b"); return true }, resume: { events.append("resume-b") })
    #expect(lease.begin())
    #expect(!lease.begin())
    lease.end(); lease.end()
    #expect(events == ["pause-a", "pause-b", "resume-b", "resume-a"])
    #expect(!lease.isPreparing)
}

@Test @MainActor func busyDeviceVetoRollsBackOnlyPreviouslyPausedOwners() {
    let lease = NotificationSetupLease()
    var restored = 0
    lease.register("a", pause: { true }, resume: { restored += 1 })
    lease.register("b", pause: { false }, resume: { Issue.record("An active device must not be restarted") })
    #expect(!lease.begin())
    #expect(restored == 1)
    #expect(!lease.isPreparing)
}
