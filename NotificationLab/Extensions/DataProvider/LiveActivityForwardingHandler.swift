// SPDX-License-Identifier: MPL-2.0
import AccessoryLiveActivities
import AccessoryTransportExtension
import ActivityKit
import Foundation

/// Snapshot retrieval is independent of ordered callbacks. Display-state retries
/// retain the same stream/revision and never include notification reply actions.
final class LiveActivityForwardingHandler: LiveActivityForwarding.AccessoryLiveActivitiesHandler,
                                          @unchecked Sendable {
    private let pipeline = LabLiveActivityPipeline()
    #if DEBUG
    // Ephemeral correlation only: never log an ActivityKit activity identifier.
    private let diagnosticHandlerID = String(UUID().uuidString.prefix(8))
    #endif

    init() {
        LabDiagnostics.record("activity", "实时活动处理器已创建", detail: "stage=handler.init")
        #if DEBUG
        debugMetadata("handler_init")
        #endif
    }

    func activate(for session: LiveActivityForwarding.Session) {
        guard LabMessageModeGate.enabled else { pipeline.invalidate(); return }
        let modeRevision = LabMessageModeGate.revision
        ForwardingDiagnostics.session(session, component: "activity")
        let generation = UUID()
        pipeline.activate(streamID: generation, snapshot: { [weak self] in
            guard LabMessageModeGate.permits(modeRevision) else { throw LabProtocolError.unavailable }
            let activities = try await session.liveActivities
            try Task.checkCancellation()
            ForwardingDiagnostics.snapshot(activities)
            #if DEBUG
            self?.debugSnapshot(activities, generation: generation)
            #endif
            return activities.prefix(32).map { Self.map($0, alert: false) }
        }, send: { event in
            guard LabMessageModeGate.permits(modeRevision) else { throw LabProtocolError.unavailable }
            try Task.checkCancellation()
            let data = try JSONEncoder().encode(event)
            try await session.send(message: AccessoryMessage {
                AccessoryMessage.Payload(transport: .bluetooth, data: data)
            })
            LabDiagnostics.record("activity", "实时活动已转发",
                detail: "kind=\(event.kind.rawValue), revision=\(event.activityRevision ?? 0), state=\(event.liveActivity?.state ?? "snapshot"), count=\(event.liveActivities?.count ?? 1), bytes=\(data.count)")
        }, report: { [weak self] report in
            self?.record(report, generation: generation)
        })
        #if DEBUG
        debugMetadata("activate", generation: generation)
        #endif
        LabDiagnostics.record("activity", "实时活动会话已激活", detail: "stage=activate")
    }

    func sessionInvalidated() {
        #if DEBUG
        debugMetadata("invalidate", generation: pipeline.streamID)
        #endif
        pipeline.invalidate()
        LabDiagnostics.record("activity", "实时活动会话已失效")
    }

    func messageReceived(_ message: TransportMessage) {
        // The public Live Activity API exposes display updates, not notification reply actions.
        LabDiagnostics.record("activity", "实时活动通道收到配件消息", detail: "bytes=\(message.data.count)")
    }

    func activityUpdated(_ activity: AccessoryLiveActivity) { enqueue(activity, alert: false) }

    func activityUpdatedForAlert(_ activity: AccessoryLiveActivity) -> Bool {
        enqueue(activity, alert: true)
        // BLE acceptance does not prove a visible alert. Keep iPhone alerting enabled.
        return false
    }

    private func enqueue(_ activity: AccessoryLiveActivity, alert: Bool) {
        guard LabMessageModeGate.enabled else { pipeline.invalidate(); return }
        let item = Self.map(activity, alert: alert)
        let event = pipeline.enqueue(item, alert: alert)
        ForwardingDiagnostics.callback(activity, alert: alert, activeSession: event != nil)
        #if DEBUG
        let callback = item.state == "dismissed" ? "remove" : alert ? "alert" : "update"
        debugMetadata("callback_\(callback)", generation: event?.activityStreamID,
            detail: "source=\(item.sourceBundleIdentifier), state=\(item.state), sessionActive=\(event != nil), hasContent=\(activity.content != nil), hasAlert=\(activity.content?.alert != nil)")
        #endif
    }

    private func record(_ report: LabLiveActivityPipeline.Report, generation: UUID) {
        let event: String
        let detail: String
        switch report {
        case .snapshotFailed(let code):
            event = "snapshot_failed"; detail = code
        case .retryScheduled(let kind, let revision, let code):
            event = "send_retry"; detail = "kind=\(kind.rawValue), revision=\(revision), attempt=2, error=\(code)"
        case .sendFailed(let kind, let revision, let code):
            event = "send_failed"; detail = "kind=\(kind.rawValue), revision=\(revision), attempts=2, error=\(code)"
        }
        #if DEBUG
        debugMetadata(event, generation: generation, detail: detail)
        #else
        LabDiagnostics.record("activity", event, detail: detail)
        #endif
    }

    #if DEBUG
    /// Inspect the system snapshot before the wire's existing 32-item limit.
    /// These counts contain no activity IDs, titles, bodies, or content states.
    private func debugSnapshot(_ activities: [AccessoryLiveActivity], generation: UUID) {
        var sources: [String: Int] = [:]
        var states: [String: Int] = [:]
        var withAlerts: [String: Int] = [:]
        var withContent: [String: Int] = [:]
        for activity in activities {
            let source = activity.sourceBundleIdentifier
            sources[source, default: 0] += 1
            states[String(describing: activity.state), default: 0] += 1
            if activity.content != nil { withContent[source, default: 0] += 1 }
            if activity.content?.alert != nil { withAlerts[source, default: 0] += 1 }
        }
        let stateCounts = states.keys.sorted().map { "\($0):\(states[$0, default: 0])" }.joined(separator: ";")
        debugMetadata("snapshot", generation: generation,
                      detail: "total=\(activities.count), sourceCount=\(sources.count), states=\(stateCounts)")
        // Separate source rows keep the diagnostic cache's line limit from
        // silently dropping source counts in a snapshot with several apps.
        for source in sources.keys.sorted() {
            debugMetadata("snapshot_source", generation: generation,
                          detail: "source=\(source), count=\(sources[source, default: 0]), hasContent=\(withContent[source, default: 0]), alert=\(withAlerts[source, default: 0]), nonalert=\(sources[source, default: 0] - withAlerts[source, default: 0])")
        }
    }

    private func debugMetadata(_ event: String, generation: UUID? = nil, detail: String = "") {
        let stream = generation.map { String($0.uuidString.prefix(8)) } ?? "none"
        LabDiagnostics.record("activity", "ALA_META \(event)",
                              detail: "handler=\(diagnosticHandlerID), stream=\(stream)\(detail.isEmpty ? "" : ", \(detail)")")
    }
    #endif

    private static func map(_ activity: AccessoryLiveActivity, alert: Bool) -> LabLiveActivity {
        let stateName: String
        switch activity.state {
        case .pending: stateName = "pending"
        case .active: stateName = "active"
        case .stale: stateName = "stale"
        case .ended: stateName = "ended"
        case .dismissed: stateName = "dismissed"
        @unknown default: stateName = "unknown"
        }
        return LabLiveActivity(activityIdentifier: activity.activityIdentifier,
                               sourceBundleIdentifier: activity.sourceBundleIdentifier,
                               sourceBundleName: activity.sourceBundleName,
                               state: stateName,
                               alertTitle: activity.content?.alert.map { String($0.title.prefix(4096)) },
                               alertBody: activity.content?.alert.map { String($0.body.prefix(8192)) },
                               shouldAlert: alert)
    }
}
