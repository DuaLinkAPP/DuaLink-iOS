// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationLabCore

private enum PipelineTestError: Error { case transient }

private actor PipelineProbe {
    private(set) var events: [LabEvent] = []
    private var failures: [String: Int]
    init(failures: [String: Int] = [:]) { self.failures = failures }
    func send(_ event: LabEvent) throws {
        events.append(event)
        let key = event.kind.rawValue
        if failures[key, default: 0] > 0 {
            failures[key, default: 0] -= 1
            throw PipelineTestError.transient
        }
    }
}

/// Deliberately ignores cancellation to model an SDK operation returning late.
private actor PipelineGate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private(set) var entered = false
    func wait() async -> Value {
        entered = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func release(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

private func eventually(_ predicate: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await predicate() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

private func activity(_ id: String = "synthetic") -> LabLiveActivity {
    LabLiveActivity(activityIdentifier: id, sourceBundleIdentifier: "test.source",
                    sourceBundleName: "Test", state: "active", alertTitle: nil,
                    alertBody: nil, shouldAlert: false)
}

@Test func blockedSnapshotDoesNotBlockMetadataOnlyCallbackAndKeepsRevisionOne() async throws {
    let gate = PipelineGate<[LabLiveActivity]>()
    let probe = PipelineProbe()
    let stream = UUID()
    let pipeline = LabLiveActivityPipeline(retryDelay: {})
    pipeline.activate(streamID: stream, snapshot: { await gate.wait() },
                      send: { try await probe.send($0) }, report: { _ in })
    let snapshotStarted = await eventually { await gate.entered }
    #expect(snapshotStarted)
    let queued = pipeline.enqueue(activity(), alert: false)
    let callbackArrived = await eventually { await probe.events.contains { $0.activityRevision == 2 } }
    await gate.release([activity()])
    let snapshotArrived = await eventually { await probe.events.count == 2 }
    pipeline.invalidate()
    let events = await probe.events
    #expect(callbackArrived && snapshotArrived)
    #expect(queued?.activityRevision == 2)
    #expect(events.map(\.activityRevision) == [2, 1])
    #expect(events.first?.liveActivity?.alertTitle == nil)
    #expect(events.first?.liveActivity?.sourceBundleIdentifier == "test.source")
    #expect(events.last?.kind == .activitySnapshot)
}

@Test func invalidationDropsAnUncancellableLateSnapshotAndFutureCallbacks() async throws {
    let gate = PipelineGate<[LabLiveActivity]>()
    let probe = PipelineProbe()
    let pipeline = LabLiveActivityPipeline(retryDelay: {})
    pipeline.activate(streamID: UUID(), snapshot: { await gate.wait() },
                      send: { try await probe.send($0) }, report: { _ in })
    let started = await eventually { await gate.entered }
    #expect(started)
    pipeline.invalidate()
    let queued = pipeline.enqueue(activity(), alert: false)
    await gate.release([activity()])
    try await Task.sleep(for: .milliseconds(20))
    #expect(queued == nil)
    #expect(await probe.events.isEmpty)
}

@Test func replacementSessionRejectsThePreviousSessionsLateSnapshot() async throws {
    let oldGate = PipelineGate<[LabLiveActivity]>()
    let probe = PipelineProbe()
    let oldStream = UUID()
    let newStream = UUID()
    let pipeline = LabLiveActivityPipeline(retryDelay: {})
    pipeline.activate(streamID: oldStream, snapshot: { await oldGate.wait() },
                      send: { try await probe.send($0) }, report: { _ in })
    let started = await eventually { await oldGate.entered }
    #expect(started)
    pipeline.activate(streamID: newStream, snapshot: { [] },
                      send: { try await probe.send($0) }, report: { _ in })
    let newArrived = await eventually { await probe.events.count == 1 }
    await oldGate.release([activity("old")])
    try await Task.sleep(for: .milliseconds(20))
    pipeline.invalidate()
    let events = await probe.events
    #expect(newArrived)
    #expect(events.count == 1)
    #expect(events.first?.activityStreamID == newStream)
}

@Test func snapshotRetriesOnceWithTheExactSameStreamRevisionAndPayload() async throws {
    let probe = PipelineProbe(failures: ["activitySnapshot": 1])
    let stream = UUID()
    let pipeline = LabLiveActivityPipeline(retryDelay: {})
    pipeline.activate(streamID: stream, snapshot: { [activity()] },
                      send: { try await probe.send($0) }, report: { _ in })
    let retried = await eventually { await probe.events.count == 2 }
    pipeline.invalidate()
    let events = await probe.events
    #expect(retried)
    #expect(events.count == 2)
    guard events.count == 2 else { return }
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(try encoder.encode(events[0]) == encoder.encode(events[1]))
    #expect(events[0].activityStreamID == stream)
    #expect(events[0].activityRevision == 1)
}

@Test func failedCallbackRetriesOnceThenAllowsTheNextCallbackToProceed() async throws {
    let gate = PipelineGate<[LabLiveActivity]>()
    let probe = PipelineProbe(failures: ["activityUpdated": 2])
    let pipeline = LabLiveActivityPipeline(retryDelay: {})
    pipeline.activate(streamID: UUID(), snapshot: { await gate.wait() },
                      send: { try await probe.send($0) }, report: { _ in })
    let started = await eventually { await gate.entered }
    #expect(started)
    pipeline.enqueue(activity("first"), alert: false)
    pipeline.enqueue(activity("second"), alert: false)
    let completed = await eventually { await probe.events.count == 3 }
    pipeline.invalidate()
    await gate.release([])
    let events = await probe.events
    #expect(completed)
    #expect(events.map(\.activityRevision) == [2, 2, 3])
    #expect(events.last?.liveActivity?.activityIdentifier == "second")
}

@Test func invalidationDuringRetryDelayPreventsSecondSendEvenWhenDelayIgnoresCancellation() async throws {
    let delay = PipelineGate<Void>()
    let probe = PipelineProbe(failures: ["activitySnapshot": 1])
    let pipeline = LabLiveActivityPipeline(retryDelay: { await delay.wait() })
    pipeline.activate(streamID: UUID(), snapshot: { [] },
                      send: { try await probe.send($0) }, report: { _ in })
    let waiting = await eventually { await delay.entered }
    #expect(waiting)
    pipeline.invalidate()
    await delay.release(())
    try await Task.sleep(for: .milliseconds(20))
    #expect(await probe.events.count == 1)
}
