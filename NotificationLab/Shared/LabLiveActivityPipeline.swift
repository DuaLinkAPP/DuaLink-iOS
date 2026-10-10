// SPDX-License-Identifier: MPL-2.0
import Foundation
import Synchronization

/// The initial snapshot can arrive after callbacks (revision 1 remains a baseline).
/// Only display-state events enter this pipeline; notification reply actions do not.
nonisolated final class LabLiveActivityPipeline: @unchecked Sendable {
    typealias Snapshot = @Sendable () async throws -> [LabLiveActivity]
    typealias Sender = @Sendable (LabEvent) async throws -> Void
    typealias Delay = @Sendable () async throws -> Void
    typealias Reporter = @Sendable (Report) -> Void

    enum Report: Sendable {
        case snapshotFailed(String)
        case retryScheduled(LabEvent.Kind, Int, String)
        case sendFailed(LabEvent.Kind, Int, String)
    }

    private struct State: Sendable {
        var streamID: UUID?
        var revision = 1
        var sender: Sender?
        var reporter: Reporter?
        var callbacks: [LabEvent] = []
        var worker: Task<Void, Never>?
        var snapshot: Task<Void, Never>?
    }
    private let state = Mutex(State())
    private let retryDelay: Delay

    init(retryDelay: @escaping Delay = { try await Task.sleep(for: .milliseconds(300)) }) {
        self.retryDelay = retryDelay
    }

    func activate(streamID: UUID, snapshot: @escaping Snapshot, send: @escaping Sender,
                  report: @escaping Reporter) {
        state.withLock { value in
            value.worker?.cancel()
            value.snapshot?.cancel()
            value = State(streamID: streamID, sender: send, reporter: report)
            // Do not put the snapshot fetch in the callback queue: the SDK read
            // may suspend even while it is already delivering fresh callbacks.
            value.snapshot = Task { [weak self] in
                do {
                    let items = try await snapshot()
                    guard let self, self.isCurrent(streamID) else { return }
                    let event = LabEvent(kind: .activitySnapshot, liveActivities: items,
                                         activityStreamID: streamID, activityRevision: 1)
                    await self.deliver(event, streamID: streamID, send: send, report: report)
                } catch {
                    guard let self, self.isCurrent(streamID) else { return }
                    report(.snapshotFailed(Self.errorCode(error)))
                }
            }
        }
    }

    /// Assign the revision synchronously in callback arrival order. One worker
    /// drains display updates; snapshot fetching never holds that worker up.
    @discardableResult
    func enqueue(_ item: LabLiveActivity, alert: Bool) -> LabEvent? {
        state.withLock { value in
            guard let streamID = value.streamID, let send = value.sender,
                  let report = value.reporter else { return nil }
            value.revision += 1
            let kind: LabEvent.Kind = item.state == "dismissed" ? .activityRemoved : alert ? .activityAlert : .activityUpdated
            let event = LabEvent(kind: kind, liveActivity: item,
                                 activityStreamID: streamID, activityRevision: value.revision)
            value.callbacks.append(event)
            if value.worker == nil {
                value.worker = Task { [weak self] in
                    await self?.drain(streamID: streamID, send: send, report: report)
                }
            }
            return event
        }
    }

    var streamID: UUID? { state.withLock { $0.streamID } }

    func invalidate() {
        state.withLock { value in
            value.worker?.cancel()
            value.snapshot?.cancel()
            value = State()
        }
    }

    private func isCurrent(_ streamID: UUID) -> Bool {
        !Task.isCancelled && state.withLock { $0.streamID == streamID }
    }

    private func drain(streamID: UUID, send: @escaping Sender, report: @escaping Reporter) async {
        while isCurrent(streamID) {
            let next = state.withLock { value -> LabEvent? in
                guard value.streamID == streamID else { return nil }
                guard !value.callbacks.isEmpty else { value.worker = nil; return nil }
                return value.callbacks.removeFirst()
            }
            guard let next else { return }
            await deliver(next, streamID: streamID, send: send, report: report)
        }
    }

    private func deliver(_ event: LabEvent, streamID: UUID, send: Sender, report: Reporter) async {
        for attempt in 0..<2 {
            guard isCurrent(streamID) else { return }
            do {
                try await send(event)
                return
            } catch {
                guard isCurrent(streamID) else { return }
                let code = Self.errorCode(error)
                if attempt == 1 {
                    report(.sendFailed(event.kind, event.activityRevision ?? 0, code))
                    return
                }
                report(.retryScheduled(event.kind, event.activityRevision ?? 0, code))
                do { try await retryDelay() } catch { return }
                // Retrying uses the exact event and revision, so the receiver's
                // idempotent activity store can ignore an ambiguous first send.
            }
        }
    }

    private static func errorCode(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) / \(error.code)"
    }
}
