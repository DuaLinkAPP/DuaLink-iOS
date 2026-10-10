// SPDX-License-Identifier: MPL-2.0
@preconcurrency import AccessoryTransportExtension
import CryptoKit
import ExtensionFoundation
import Foundation

@main
struct NotificationSecurityExtension: AccessoryTransportSecurity {
    init() {
        LabDiagnostics.record("security", "安全扩展实例已创建", detail: "stage=extension.init")
    }

    @AppExtensionPoint.Bind
    static var boundExtensionPoint: AppExtensionPoint {
        Identifier("com.apple.accessory-transport-security")
    }

    func accept(sessionRequest: AccessorySecuritySession.Request) -> AccessorySecuritySession.Request.Decision {
        LabDiagnostics.record("security", "收到系统安全会话请求", detail: "stage=accept")
        guard LabMessageModeGate.enabled else { return sessionRequest.reject(error: .unsupported) }
        return sessionRequest.accept { NotificationSecurityHandler(session: sessionRequest.session) }
    }
}

/// session 与密钥交换状态仅在 connection 的串行 executor 上使用。
final class NotificationSecurityHandler: AccessorySecuritySession.EventHandler, @unchecked Sendable {
    private let session: AccessorySecuritySession
    private let connection = LabAccessoryConnection(channel: .security)
    private var invalidated = false
    private let modeRevision = LabMessageModeGate.revision
    private var publicKeyAccepted = false

    init(session: AccessorySecuritySession) {
        self.session = session
        connection.start(onReceive: { [weak self] message in self?.receive(message) }, onFailure: { [weak self] in
            self?.session.cancel(error: .unknown)
        })
        LabDiagnostics.record("security", "密钥交换扩展已启动", detail: "stage=handler.init")
    }

    func messageReceived(_ message: SecurityMessage, completion: @escaping @Sendable (AccessoryMessage.Result) -> Void) {
        connection.perform { [self] in
            let suppliedIdentifier = message.identifier.flatMap { value in
                value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
            }
            LabDiagnostics.record("security", "收到系统密钥消息元数据",
                detail: "keyType=\(message.keyType.rawValue), suite=\(message.cipherSuite.description), version=\(message.version.description), keyBytes=\(message.key.count), hasIdentifier=\(suppliedIdentifier != nil)")
            guard !invalidated, LabMessageModeGate.permits(modeRevision), message.keyType == .encapsulatedKey else {
                completion(.failure(.transportFailed)); return
            }
            // SDK descriptions are diagnostic text, not this accessory's wire codec.
            switch (message.cipherSuite, message.version) {
            case (.p256, .version1): break
            default:
                LabDiagnostics.record("security", "系统返回了不支持的密钥套件")
                completion(.failure(.transportFailed)); return
            }
            do {
                // 配件不知道 iPhone 侧的 CBPeripheral UUID；系统未返回 identifier 时显式传出它。
                guard let identifier = suppliedIdentifier ?? connection.approvedID?.uuidString else {
                    completion(.failure(.transportFailed)); return
                }
                let payload = LabSecurityPayload(keyType: "encapsulatedKey",
                    cipherSuite: "p256", version: "Version1",
                    key: message.key, identifier: identifier,
                    protocolInfo: "\(message.cipherSuite.description)-\(message.version.description)-\(identifier)")
                LabDiagnostics.record("security", "传出系统 HPKE 上下文",
                    detail: "suite=\(message.cipherSuite.description), version=\(message.version.description)")
                let envelope = LabEnvelope(kind: .security, payload: try JSONEncoder().encode(payload))
                connection.send(envelope) { result in
                    switch result {
                    case .success:
                        LabDiagnostics.record("security", "系统密钥材料已传给配件")
                        completion(.success)
                    case .failure: completion(.failure(.transportFailed))
                    }
                }
            } catch { completion(.failure(.transportFailed)) }
        }
    }

    func sessionInvalidated(error: AccessorySecuritySession.Error?) {
        connection.perform { [self] in
            invalidated = true
            connection.stop()
            LabDiagnostics.record("security", "密钥会话已失效")
        }
    }

    private func receive(_ envelope: LabEnvelope) {
        guard !invalidated, LabMessageModeGate.permits(modeRevision), !publicKeyAccepted, envelope.kind == .security else { return }
        do {
            let payload = try JSONDecoder().decode(LabSecurityPayload.self, from: envelope.payload)
            // 初版仅支持 Apple 文档允许的 BLE P256 套件，不生成或导出配件私钥。
            guard payload.keyType == "publicKey", payload.cipherSuite == "p256", payload.version == "Version1",
                  payload.identifier == nil else { throw LabProtocolError.invalidKey }
            let systemPublicKey = try LabP256PublicKey.appleRawRepresentation(fromWireKey: payload.key)
            try session.sendSecurityMessage(SecurityMessage(keyType: .publicKey, cipherSuite: .p256,
                version: .version1, key: systemPublicKey, supportedTransports: [.bluetooth]))
            publicKeyAccepted = true
            LabDiagnostics.record("security", "配件公钥已交给系统")
        } catch {
            LabDiagnostics.record("security", "密钥交换失败", detail: LabDiagnostics.errorCode(error))
            session.cancel(error: .unsupported)
            connection.stop()
        }
    }
}
