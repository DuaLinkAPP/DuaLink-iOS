// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
import Foundation
import OSLog

@available(iOS 26.5, *)
extension NotificationInteropModel {
    func reconnect() { checkConnection(mode: .notificationService) }

    func restoreSystemConnection() {
        guard canManage, !reconnecting else { return }
        checkConnection(mode: .systemServices)
    }

    func checkConnection(mode: NotificationReconnectMode, automatic: Bool = false) {
        guard canManage, !reconnecting, let identifier = accessory?.bluetoothIdentifier else { return }
        if !automatic { cancelPermissionCheck() }
        reconnectRevision += 1
        let revision = reconnectRevision
        reconnectOwnsBusy = !automatic
        if reconnectOwnsBusy { busy = true }
        reconnecting = true
        reconnectMode = mode
        connectionNotice = mode == .systemServices
            ? "正在恢复系统连接，请留意 iPhone 的系统通知共享提示。"
            : automatic ? "正在连接已添加的鸿蒙手机…" : "正在重新连接，请保持鸿蒙 DuaLink 的通知回复开启…"
        reconnectController.connect(to: identifier, mode: mode,
            ancsAuthorizationChanged: { [weak self] authorized in
                guard let self, revision == self.reconnectRevision,
                      self.accessory?.bluetoothIdentifier == identifier else { return }
                // If discovery is still running, the final callback will include
                // this value. After completion, reflect a later system decision.
                guard !self.reconnecting else { return }
                self.connectionNotice = NotificationConnectionNotice.systemServicesFound(ancsAuthorized: authorized)
                self.refreshRegisteredAccessoryPermissions()
            }) { [weak self] result in
            guard let self, revision == self.reconnectRevision else { return }
            if self.reconnectOwnsBusy { self.busy = false }
            self.reconnectOwnsBusy = false
            self.reconnecting = false
            switch result {
            case .success(let evidence):
                self.connectionNotice = evidence.ancsAuthorized.map {
                    NotificationConnectionNotice.systemServicesFound(ancsAuthorized: $0)
                } ?? NotificationConnectionNotice.serviceFound
            case .failure(let error):
                self.connectionNotice = self.reconnectFailureNotice(error)
            }
            #if DEBUG
            UserDefaults.standard.set(self.connectionNotice, forKey: "interop.debug.reconnectResult")
            UserDefaults.standard.set(mode == .systemServices, forKey: "interop.debug.systemConnectionRepair")
            UserDefaults.standard.set(automatic, forKey: "interop.debug.automaticConnectionAttempt")
            #endif
            self.refreshRegisteredAccessoryPermissions()
        }
    }

    private func refreshRegisteredAccessoryPermissions() {
        guard ready, let session else { return }
        accessories = session.accessories
        resolvePermissionDevice()
        refreshDeviceNames()
        refresh()
    }

    private func reconnectFailureNotice(_ error: any Error) -> String {
        if error is CancellationError { return NotificationConnectionNotice.message(for: .cancelled) }
        let systemError = error as NSError
        technicalDetail = "\(systemError.domain) / \(systemError.code)"
        logger.error("Notification reconnect failed: \(self.technicalDetail, privacy: .public)")
        #if DEBUG
        UserDefaults.standard.set(technicalDetail, forKey: "interop.debug.reconnectError")
        #endif
        guard let localError = error as? NotificationReconnectController.ReconnectError else {
            return NotificationConnectionNotice.systemFailure(systemError)
        }
        switch localError {
        case .setupInProgress: return NotificationConnectionNotice.message(for: .setupInProgress)
        case .unavailable: return NotificationConnectionNotice.message(for: .unavailable)
        case .timedOut: return NotificationConnectionNotice.message(for: .timedOut)
        case .serviceMissing: return NotificationConnectionNotice.message(for: .serviceMissing)
        }
    }

    /// Called on navigation away and before destructive removal. Only our
    /// temporary central is released; the system transport extensions retain theirs.
    func stopReconnect() {
        reconnectRevision += 1
        let wasReconnecting = reconnecting
        let ownedBusy = reconnectOwnsBusy
        reconnecting = false
        reconnectOwnsBusy = false
        reconnectController.stop()
        if ownedBusy { busy = false }
        if wasReconnecting { connectionNotice = nil }
    }

    func removeAccessory(_ target: ASAccessory) {
        guard ready, !busy, let session,
              accessories.contains(where: { $0.bluetoothIdentifier == target.bluetoothIdentifier }) else { return }
        stopReconnect()
        busy = true
        cancelPermissionCheck()
        let revision = generation
        session.removeAccessory(target) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.generation == revision else { return }
                self.busy = false
                if let error { self.report(error); return }
                self.accessories = session.accessories
                self.resolvePermissionDevice()
                self.lastChecked = nil
                self.connectionNotice = nil
                if let identifier = target.bluetoothIdentifier {
                    self.deviceNames.removeValue(forKey: identifier.uuidString)
                    UserDefaults.standard.set(self.deviceNames, forKey: "interop.deviceNames")
                }
                UserDefaults.standard.set(false, forKey: "interop.setup.pairingConfirmed")
                UserDefaults.standard.set(false, forKey: "interop.setup.harmonyPrepared")
                self.notice = "已取消配对。再次使用时，请检查两端系统蓝牙配对，再添加手机并允许通知转发。"
            }
        }
    }
}
