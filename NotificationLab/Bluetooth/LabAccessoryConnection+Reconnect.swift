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
}
