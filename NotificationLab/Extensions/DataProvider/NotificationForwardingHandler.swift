// SPDX-License-Identifier: MPL-2.0
import AccessoryNotifications
import AccessoryTransportExtension
import Foundation
import Synchronization

/// 系统同步生命周期回调必须立即更新状态；Mutex 避免 Task 调度重排导致使用过期会话。
final class NotificationForwardingHandler: NotificationsForwarding.AccessoryNotificationsHandler {
    private struct State: Sendable {
        var session: NotificationsForwarding.Session?
        var generation = UUID()
        var modeRevision = LabMessageModeGate.revision
        var notifications: [LabNotificationKey: LabNotification] = [:]
        var ledger = LabResponseLedger()
    }
    private struct SessionSnapshot: Sendable {
        let session: NotificationsForwarding.Session
        let generation: UUID
        let modeRevision: UUID?
    }
    private let state = Mutex(State())

    func didActivate(for session: NotificationsForwarding.Session) {
        guard LabMessageModeGate.enabled else { state.withLock { $0 = State() }; return }
        state.withLock { $0 = State(session: session) }
        ForwardingDiagnostics.session(session, component: "provider")
        LabDiagnostics.record("provider", "通知会话已激活")
    }

    func didInvalidate() {
        state.withLock { $0 = State() }
        LabDiagnostics.record("provider", "通知会话已失效，旧动作已清除")
    }

    func addNotification(_ notification: AccessoryNotification, alertingContext: AlertingContext) async throws -> Bool {
        guard LabMessageModeGate.enabled else { return false }
        let item = LabNotification(notification, shouldAlert: alertingContext.shouldAlert)
        let snapshot = try remember(item)
        let kinds = item.actions.map { $0.kind.rawValue }.joined(separator: ",")
        LabDiagnostics.record("provider", "收到系统通知",
            detail: "sourceName=\(item.sourceName), sourceIdentifier=\(item.key.sourceIdentifier), actions=\(item.actions.count), kinds=\(kinds)")
        do {
            try await send(LabEvent(kind: .added, notification: item), through: snapshot)
        } catch {
            LabDiagnostics.record("provider", "系统通知发送失败", detail: LabDiagnostics.errorCode(error))
            throw error
        }
        // 写入成功不能代替配件实际提醒确认。此阶段没有配件显示回执，所以不宣称已提醒。
        return false
    }

    func updateNotification(_ notification: AccessoryNotification) {
        let item = LabNotification(notification, shouldAlert: false)
        do {
            let snapshot = try remember(item)
            let kinds = item.actions.map { $0.kind.rawValue }.joined(separator: ",")
            // Source application metadata only; never log message title/body/sender.
            LabDiagnostics.record("provider", "收到系统通知更新",
                detail: "sourceName=\(item.sourceName), sourceIdentifier=\(item.key.sourceIdentifier), actions=\(item.actions.count), kinds=\(kinds)")
            forward(LabEvent(kind: .updated, notification: item), through: snapshot)
        } catch { reportProviderError(error) }
    }

    func removeNotification(identifier: AccessoryNotification.Identifier) {
        let key = LabNotificationKey(sourceIdentifier: identifier.sourceIdentifier,
                                     notificationIdentifier: identifier.notificationIdentifier)
        let snapshot = state.withLock { value -> SessionSnapshot? in
            value.notifications.removeValue(forKey: key)
            return value.session.map { SessionSnapshot(session: $0, generation: value.generation, modeRevision: value.modeRevision) }
        }
        if let snapshot { forward(LabEvent(kind: .removed, key: key), through: snapshot) }
    }

    func removeAllNotifications() {
        let snapshot = state.withLock { value -> SessionSnapshot? in
            value.notifications.removeAll()
            return value.session.map { SessionSnapshot(session: $0, generation: value.generation, modeRevision: value.modeRevision) }
        }
        if let snapshot { forward(LabEvent(kind: .removeAll), through: snapshot) }
    }

    func messageHandler(_ message: TransportMessage) {
        guard LabMessageModeGate.enabled else { return }
        var decodedResponse: LabResponse?
        do {
            guard message.data.count <= LabProtocol.maxFrameBytes else { throw LabProtocolError.frameTooLarge }
            let response = try JSONDecoder().decode(LabResponse.self, from: message.data)
            decodedResponse = response
            let prepared = try state.withLock { value -> (SessionSnapshot, String?) in
                guard LabMessageModeGate.permits(value.modeRevision),
                      let session = value.session else { throw LabProtocolError.unavailable }
                if #available(iOS 27.0, *), session.sessionID != message.sessionID {
                    throw LabProtocolError.unavailable
                }
                guard let notification = value.notifications[response.key] else {
                    throw LabProtocolError.unknownNotification
                }
                try response.validate(against: notification)
                let duplicateResult = try value.ledger.reserve(response.requestID)
                return (SessionSnapshot(session: session, generation: value.generation, modeRevision: value.modeRevision), duplicateResult)
            }
            if let duplicateResult = prepared.1 {
                forward(LabEvent(kind: .result, requestID: response.requestID, result: duplicateResult), through: prepared.0)
                return
            }
            Task { await execute(response, through: prepared.0) }
        } catch {
            LabDiagnostics.record("response", "拒绝无效回复", detail: LabDiagnostics.errorCode(error))
            if let response = decodedResponse, let validationError = error as? LabProtocolError {
                forwardRejection(response, error: validationError, sessionID: message.sessionID)
            }
        }
    }

    private func forwardRejection(_ response: LabResponse, error: LabProtocolError, sessionID: UUID) {
        let snapshot = state.withLock { value -> SessionSnapshot? in
            guard let session = value.session else { return nil }
            // Fail closed when the SDK cannot confirm the response's active session.
            guard #available(iOS 27.0, *), session.sessionID == sessionID else { return nil }
            return SessionSnapshot(session: session, generation: value.generation, modeRevision: value.modeRevision)
        }
        guard let snapshot else { return }
        Task {
            do {
                if error == .unknownNotification {
                    // Retire only the accessory's stale card. Never remove the
                    // original iPhone notification or execute its stale action.
                    try await send(LabEvent(kind: .removed, key: response.key), through: snapshot)
                }
                try await send(LabEvent(kind: .result, key: response.key,
                    requestID: response.requestID, result: error.rawValue), through: snapshot)
            } catch {
                reportProviderError(error)
            }
        }
    }

    private func remember(_ notification: LabNotification) throws -> SessionSnapshot {
        try state.withLock { value in
            guard LabMessageModeGate.permits(value.modeRevision),
                  let session = value.session else { throw LabProtocolError.unavailable }
            guard value.notifications[notification.key] != nil || value.notifications.count < 128 else {
                throw LabProtocolError.queueFull
            }
            value.notifications[notification.key] = notification
            return SessionSnapshot(session: session, generation: value.generation, modeRevision: value.modeRevision)
        }
    }

    private func isCurrent(_ snapshot: SessionSnapshot) -> Bool {
        LabMessageModeGate.permits(snapshot.modeRevision) &&
            state.withLock { $0.generation == snapshot.generation && $0.session != nil }
    }

    private func execute(_ response: LabResponse, through snapshot: SessionSnapshot) async {
        guard isCurrent(snapshot) else { return }
        let systemResponse = NotificationResponse(sourceIdentifier: response.key.sourceIdentifier,
            notificationIdentifier: response.key.notificationIdentifier,
            actionIdentifier: response.actionIdentifier, userText: response.userText)
        let result: String
        do {
            // 排队期间通知可能已撤回或更新；调用系统前再次核对最新动作。
            try state.withLock { value in
                guard value.generation == snapshot.generation else { throw LabProtocolError.unavailable }
                guard let notification = value.notifications[response.key] else {
                    throw LabProtocolError.unknownNotification
                }
                try response.validate(against: notification)
            }
            guard isCurrent(snapshot) else { return }
            try await snapshot.session.sendResponse(systemResponse)
            result = "systemAccepted"
            LabDiagnostics.record("response", "系统已接受动作", detail: "仍需源应用或接收方确认业务结果")
        } catch {
            // 不自动重试有副作用的动作，避免在结果不明确时重复发送消息。
            result = "systemError"
            LabDiagnostics.record("response", "系统回复接口返回错误", detail: LabDiagnostics.errorCode(error))
        }
        state.withLock { value in
            guard value.generation == snapshot.generation else { return }
            value.ledger.finish(response.requestID, result: result)
        }
        forward(LabEvent(kind: .result, requestID: response.requestID, result: result), through: snapshot)
    }

    private func forward(_ event: LabEvent, through snapshot: SessionSnapshot) {
        Task {
            do { try await send(event, through: snapshot) }
            catch { reportProviderError(error) }
        }
    }

    private func send(_ event: LabEvent, through snapshot: SessionSnapshot) async throws {
        guard isCurrent(snapshot) else { throw LabProtocolError.unavailable }
        let bytes = try JSONEncoder().encode(event)
        guard bytes.count <= 64 * 1024 else { throw LabProtocolError.frameTooLarge }
        try await snapshot.session.send(message: AccessoryMessage {
            AccessoryMessage.Payload(transport: .bluetooth, data: bytes)
        })
    }

    private func reportProviderError(_ error: any Error) {
        LabDiagnostics.record("provider", "通知转发失败", detail: LabDiagnostics.errorCode(error))
    }
}
