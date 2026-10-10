// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
@preconcurrency import CoreBluetooth
import Foundation

// 委托由创建 CBCentralManager 时指定的 executor 调用，保持单队列状态机。
extension LabAccessoryConnection: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopped, central === self.central else { return }
        recordStage("BLE 中央状态更新", detail: "state=\(central.state.rawValue), authorization=\(CBManager.authorization.rawValue)")
        switch central.state {
        case .poweredOn: connectApprovedAccessory()
        case .unsupported, .unauthorized: fail(.unavailable)
        case .poweredOff:
            if hasEstablishedConnection || ready {
                fail(.unavailable)
            } else {
                // Keep the existing 20-second startup deadline while ASK/CB
                // settle; a first poweredOff callback is not proof the radio is off.
                recordStage("等待 BLE 启动授权就绪", detail: "state=4, startupDeadline=20s")
            }
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard !stopped, central === self.central else { return }
        restoredPeripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        recordStage("BLE 状态恢复", detail: "peripherals=\(restoredPeripherals.count)")
        // 仍只接受由 ASK 授权的唯一设备，不能根据系统恢复列表任意选择接收者。
        connectApprovedAccessory()
    }

    func centralManager(_ central: CBCentralManager, didDiscover candidate: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard !stopped, central === self.central else { return }
        let wasSeen = targetPolicy?.advertisementSeen == true
        guard targetPolicy?.observeAdvertisement(from: candidate.identifier) == true else { return }
        if !wasSeen { recordStage("广播中发现已登记目标", detail: targetPolicy?.summary ?? "") }
        // A pending cached connect stays intact. Only an absent cached object
        // needs its first connection submitted from this discovery callback.
        submitApprovedConnection(candidate, source: "advertisement")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !stopped, central === self.central, peripheral === self.peripheral,
              peripheral.identifier == approvedID, targetPolicy?.connectionConfirmed != true else { return }
        hasEstablishedConnection = true
        _ = targetPolicy?.confirmConnection(to: peripheral.identifier)
        central.stopScan()
        recordStage("BLE 配件已连接", detail: "stage=didConnect, \(targetPolicy?.summary ?? "")")
        armDeadline(seconds: 20)
        peripheral.discoverServices([CBUUID(string: LabProtocol.service)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        guard !stopped, central === self.central, peripheral === self.peripheral else { return }
        recordStage("BLE 连接失败", detail: error.map { LabDiagnostics.errorCode($0) } ?? "none")
        if reconnectTransport() { return }
        fail(.unavailable)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        guard !stopped, central === self.central, peripheral === self.peripheral else { return }
        recordStage("BLE 配件断开", detail: error.map { LabDiagnostics.errorCode($0) } ?? "none")
        if reconnectTransport() { return }
        fail(.unavailable)
    }

    // Service Changed invalidates old CBService/characteristic objects. A reply
    // connection must rediscover its own profile without touching other clients.
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard !stopped, !reconnectPolicy.waitingForProfileDisconnect, peripheral === self.peripheral,
              invalidatedServices.contains(where: { $0.uuid == CBUUID(string: LabProtocol.service) }) else { return }
        recordStage("配件服务已变更，重新发现回复特征")
        // Neither an outgoing partial frame nor an incoming partial reply can
        // safely continue on a new GATT database.
        guard LabReconnectPolicy.canResume(writeOffsets: writes.map(\.offset), waitingForWrite: waitingForWrite,
                                           hasPendingReceive: receiveBuffer.hasPendingFrame)
        else { fail(.unavailable); return }
        subscription.reset()
        activeService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        resetReceiveBuffer()
        armDeadline(seconds: 20)
        peripheral.discoverServices([CBUUID(string: LabProtocol.service)])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard !stopped, !reconnectPolicy.waitingForProfileDisconnect, peripheral === self.peripheral,
              activeService == nil else { return }
        recordStage("BLE 服务发现结果", detail: "count=\(peripheral.services?.count ?? 0), error=\(error.map { LabDiagnostics.errorCode($0) } ?? "none")")
        guard error == nil else { fail(.unavailable); return }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == CBUUID(string: LabProtocol.service)
        }) else {
            if reconnectIncompleteProfile() { return }
            fail(.unavailable); return
        }
        activeService = service
        armDeadline(seconds: 20)
        // This dedicated profile has four characteristics. Discover the complete
        // profile so a previous partial security/data discovery is not reused.
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard !stopped, !reconnectPolicy.waitingForProfileDisconnect, peripheral === self.peripheral,
              service === activeService, !subscription.hasStarted else { return }
        writeCharacteristic = service.characteristics?.first { $0.uuid == CBUUID(string: channel.writeUUID) }
        notifyCharacteristic = service.characteristics?.first { $0.uuid == CBUUID(string: channel.notifyUUID) }
        recordStage("BLE 特征发现结果", detail: "count=\(service.characteristics?.count ?? 0), writeFound=\(writeCharacteristic != nil), notifyFound=\(notifyCharacteristic != nil), error=\(error.map { LabDiagnostics.errorCode($0) } ?? "none")")
        guard error == nil else { fail(.unavailable); return }
        guard let writeCharacteristic, writeCharacteristic.properties.contains(.write),
              let notifyCharacteristic, notifyCharacteristic.properties.contains(.notify) ||
                notifyCharacteristic.properties.contains(.indicate) else {
            if reconnectIncompleteProfile() { return }
            fail(.unavailable); return
        }
        armDeadline(seconds: 20)
        let action = subscription.prepare(isData: channel == .data, isNotifying: notifyCharacteristic.isNotifying)
        peripheral.setNotifyValue(action != .disable, for: notifyCharacteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard !stopped, peripheral === self.peripheral,
              characteristic === notifyCharacteristic else { return }
        recordStage("BLE 订阅状态更新", detail: "notifying=\(characteristic.isNotifying), error=\(error.map { LabDiagnostics.errorCode($0) } ?? "none")")
        guard error == nil, LabMessageModeGate.permits(modeRevision) else { fail(.unavailable); return }
        switch subscription.observed(isNotifying: characteristic.isNotifying) {
        case .none: return
        case .enable:
            armDeadline(seconds: 20)
            peripheral.setNotifyValue(true, for: characteristic)
        case .ready:
            cancelDeadline()
            LabDiagnostics.record(channel == .data ? "transport" : "security", "BLE 订阅已就绪")
            pumpWrites()
        case .lost, .disable:
            fail(.unavailable)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard !stopped, peripheral === self.peripheral, characteristic === writeCharacteristic,
              waitingForWrite, !writes.isEmpty else { return }
        guard error == nil, LabMessageModeGate.permits(modeRevision) else { fail(.unavailable); return }
        waitingForWrite = false
        cancelDeadline()
        if writes[0].offset == writes[0].bytes.count {
            let write = writes.removeFirst()
            reconnectPolicy.didDeliverFrame()
            write.completion(.success(()))
        }
        pumpWrites()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: (any Error)?) {
        guard !stopped, peripheral === self.peripheral,
              characteristic === notifyCharacteristic else { return }
        guard error == nil, let bytes = characteristic.value else { fail(.unavailable); return }
        receive(bytes)
    }
}
