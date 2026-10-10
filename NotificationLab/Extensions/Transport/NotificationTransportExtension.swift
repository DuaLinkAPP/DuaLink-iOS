// SPDX-License-Identifier: MPL-2.0
@preconcurrency import AccessoryTransportExtension
import ExtensionFoundation
import Foundation

@main
struct NotificationTransportExtension: AccessoryTransportAppExtension {
    init() {
        LabDiagnostics.record("transport", "传输扩展实例已创建", detail: "stage=extension.init")
    }

    @AppExtensionPoint.Bind
    static var boundExtensionPoint: AppExtensionPoint {
        Identifier("com.apple.accessory-transport-extension")
    }

    func accept(sessionRequest: AccessoryTransportSession.Request) -> AccessoryTransportSession.Request.Decision {
        LabDiagnostics.record("transport", "收到系统传输会话请求", detail: "stage=accept")
        guard LabMessageModeGate.enabled else { return sessionRequest.reject(error: .unsupported) }
        return sessionRequest.accept { NotificationTransportHandler(session: sessionRequest.session) }
    }
}

/// session 的所有操作由 connection 的串行 executor 保护；系统回调只投递任务。
final class NotificationTransportHandler: AccessoryTransportSession.EventHandler, @unchecked Sendable {
    private let session: AccessoryTransportSession
    private let connection: LabAccessoryConnection
    private var activeSessionIDs = Set<UUID>()
    private var invalidated = false
    private let modeRevision = LabMessageModeGate.revision

    init(session: AccessoryTransportSession) {
        self.session = session
        self.connection = LabAccessoryConnection(channel: .data, restoreIdentifier: session.transportStateRestoreIdentifier)
        connection.start(onReceive: { [weak self] envelope in self?.receive(envelope) }, onFailure: { [weak self] in
            self?.session.cancel(error: .unknown)
        })
        LabDiagnostics.record("transport", "传输扩展已启动", detail: "stage=handler.init")
    }

    func messageReceived(_ message: TransportMessage, completion: @escaping @Sendable (AccessoryMessage.Result) -> Void) {
        connection.perform { [self] in
            LabDiagnostics.record("transport", "收到系统传输密文",
                                  detail: "bytes=\(message.data.count), trackedSessions=\(activeSessionIDs.count)")
            guard !invalidated, LabMessageModeGate.permits(modeRevision) else {
                completion(.failure(.transportUnavailable)); connection.stop(); session.cancel(error: .unsupported); return
            }
            activeSessionIDs.insert(message.sessionID)
            guard activeSessionIDs.count <= 16 else {
                completion(.failure(.transportFailed))
                session.cancel(error: .unsupported)
                return
            }
            let envelope = LabEnvelope(kind: .ciphertext, sessionID: message.sessionID, payload: message.data)
            connection.send(envelope) { result in
                switch result {
                case .success:
                    LabDiagnostics.record("transport", "密文已写入配件", detail: "不代表通知已显示或动作已执行")
                    completion(.success)
                case .failure: completion(.failure(.transportFailed))
                }
            }
        }
    }

    func sessionInvalidated(error: AccessoryTransportSession.Error?) {
        connection.perform { [self] in
            invalidated = true
            activeSessionIDs.removeAll()
            connection.stop()
            LabDiagnostics.record("transport", "传输会话已失效",
                                  detail: error.map { LabDiagnostics.errorCode($0) } ?? "none")
        }
    }

    private func receive(_ envelope: LabEnvelope) {
        guard !invalidated, LabMessageModeGate.permits(modeRevision), envelope.kind == .ciphertext, let identifier = envelope.sessionID,
              activeSessionIDs.contains(identifier) else {
            LabDiagnostics.record("transport", "拒绝未知会话的回传")
            return
        }
        do {
            // 保持密文交给系统解密，不在传输扩展解释通知动作。
            try session.sendMessageToDataProvider(TransportMessage(sessionID: identifier, data: envelope.payload))
            LabDiagnostics.record("transport", "配件密文已交给系统")
        } catch {
            LabDiagnostics.record("transport", "系统拒绝回传", detail: LabDiagnostics.errorCode(error))
        }
    }
}
