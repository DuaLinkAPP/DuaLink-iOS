// SPDX-License-Identifier: MPL-2.0
@preconcurrency import CoreBluetooth
import Foundation

extension LabAccessoryConnection {
    /// Submit before returning from the Bluetooth callback. The system can
    /// suspend this extension immediately afterward; an asyncAfter timer would
    /// leave CoreBluetooth with no pending connection to restore or wake us for.
    func reconnectTransport() -> Bool {
        guard !stopped, channel == .data, hasEstablishedConnection,
              central?.state == .poweredOn, approvedID != nil,
              reconnectPolicy.beginRecovery(writeOffsets: writes.map(\.offset), waitingForWrite: waitingForWrite,
                  hasPendingReceive: receiveBuffer.hasPendingFrame)
        else { return false }
        subscription.reset()
        subscriptionProbe.reset()
        subscriptionDescriptor = nil
        peripheral?.delegate = nil
        peripheral = nil
        if let approvedID { targetPolicy = LabApprovedTargetPolicy(approvedID: approvedID) }
        restoredPeripherals.removeAll()
        activeService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        resetReceiveBuffer()
        armDeadline(seconds: 20)
        recordStage("传输连接立即恢复", detail: "attempt=\(reconnectPolicy.attempts), unsentFrames=\(writes.count)")
        connectApprovedAccessory()
        return true
    }

    /// Reacquire only our central's connection once. Repeating discovery on the
    /// same stale service in a tight loop cannot invalidate the system's cache.
    /// This public-API attempt does not promise a physical disconnect/cache reset.
    func reconnectIncompleteProfile() -> Bool {
        guard !stopped, channel == .data, let central, let peripheral,
              peripheral.state == .connected,
              reconnectPolicy.beginProfileRecovery(writeOffsets: writes.map(\.offset), waitingForWrite: waitingForWrite,
                  hasPendingReceive: receiveBuffer.hasPendingFrame)
        else { return false }
        subscription.reset()
        subscriptionProbe.reset()
        subscriptionDescriptor = nil
        peripheral.delegate = nil
        activeService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        resetReceiveBuffer()
        armDeadline(seconds: 20)
        recordStage("配件服务暂未完整，重新获取本地连接", detail: "attempt=\(reconnectPolicy.attempts), waitingForDisconnect=true")
        // Keep the peripheral until didDisconnect arrives. That callback invokes
        // reconnectTransport synchronously, retaining the same ASK and central.
        central.cancelPeripheralConnection(peripheral)
        return true
    }
    /// A registered server can survive on the shared ACL while the peer process
    /// loses its CCCD. Query the remote descriptor instead of cycling a live stream.
    func readRemoteSubscription() {
        guard !stopped, let peripheral, let notifyCharacteristic else { fail(.unavailable); return }
        subscriptionDescriptor = nil
        armDeadline(seconds: 10)
        recordStage("核对远端回复订阅")
        peripheral.discoverDescriptors(for: notifyCharacteristic)
    }

    func retrySubscriptionSetup() -> Bool {
        subscriptionProbe.reset()
        subscriptionDescriptor = nil
        return reconnectIncompleteProfile()
    }

    func acceptRemoteSubscription(_ value: Int) {
        switch subscriptionProbe.complete(value) {
        case .subscribed:
            subscriptionDescriptor = nil
            cancelDeadline()
            recordStage("远端回复订阅仍有效")
            pumpWrites()
        case .renew:
            subscriptionDescriptor = nil
            guard LabReconnectPolicy.canResume(writeOffsets: writes.map(\.offset), waitingForWrite: waitingForWrite,
                                                hasPendingReceive: receiveBuffer.hasPendingFrame),
                  let peripheral, let notifyCharacteristic else { fail(.unavailable); return }
            subscription.reset()
            let action = subscription.prepare(isData: true, isNotifying: notifyCharacteristic.isNotifying)
            armDeadline(seconds: 20)
            recordStage("远端订阅已丢失，恢复回复订阅")
            peripheral.setNotifyValue(action != .disable, for: notifyCharacteristic)
        case .invalid:
            if retrySubscriptionSetup() { return }
            fail(.unavailable)
        }
    }
}
