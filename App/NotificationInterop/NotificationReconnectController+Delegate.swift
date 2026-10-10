// SPDX-License-Identifier: MPL-2.0
import CoreBluetooth
import Foundation

extension NotificationReconnectController: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central, completion != nil else { return }
        recordStage("BLE 中央状态更新", detail: "state=\(central.state.rawValue)")
        switch central.state {
        case .poweredOn: connectWhenReady()
        case .unauthorized, .unsupported: finish(.failure(ReconnectError.unavailable))
        default: break // ASK can briefly report poweredOff during initialization; keep the deadline.
        }
    }

    func connectWhenReady() {
        guard let central, central.state == .poweredOn, completion != nil,
              !connectStarted, let target else { return }
        let matches = central.retrievePeripherals(withIdentifiers: [target]).filter { $0.identifier == target }
        recordStage("检索已授权 BLE 配件", detail: "approvedMatches=\(matches.count)")
        if let phone = matches.first { submitApprovedConnection(phone, source: "retrieved") }
        if !central.isScanning {
            central.scanForPeripherals(withServices: [serviceID])
            recordStage("开始扫描已登记目标的广播")
        }
    }

    private func submitApprovedConnection(_ phone: CBPeripheral, source: String) {
        guard let central, central.state == .poweredOn, completion != nil,
              targetPolicy?.submitConnection(to: phone.identifier) == true else { return }
        connectStarted = true
        peripheral = phone
        phone.delegate = self
        recordStage("提交已登记目标连接", detail: "source=\(source), peripheralState=\(phone.state.rawValue)")
        central.connect(phone, options: mode.options(
            ancsKey: CBConnectPeripheralOptionRequiresANCS,
            bridgingKey: CBConnectPeripheralOptionEnableTransportBridgingKey))
    }

    func centralManager(_ central: CBCentralManager, didDiscover candidate: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === self.central, completion != nil else { return }
        let wasSeen = targetPolicy?.advertisementSeen == true
        guard targetPolicy?.observeAdvertisement(from: candidate.identifier) == true else { return }
        if !wasSeen { recordStage("广播中发现已登记目标", detail: targetPolicy?.summary ?? "") }
        // Preserve a cached pending request. Scan discovery may only submit
        // the first request when retrievePeripherals had no matching object.
        submitApprovedConnection(candidate, source: "advertisement")
    }

    func centralManager(_ central: CBCentralManager, didUpdateANCSAuthorizationFor peripheral: CBPeripheral) {
        guard central === self.central, peripheral === self.peripheral,
              peripheral.identifier == target, mode == .systemServices else { return }
        ancsAuthorizationChanged?(peripheral.ancsAuthorized)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, peripheral === self.peripheral, completion != nil else { return }
        _ = targetPolicy?.confirmConnection(to: peripheral.identifier)
        central.stopScan()
        recordStage("BLE 配件已连接", detail: targetPolicy?.summary ?? "")
        peripheral.discoverServices([serviceID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, peripheral === self.peripheral else { return }
        recordStage("BLE 连接失败", detail: error.map { "\(($0 as NSError).domain) / \(($0 as NSError).code)" } ?? "none")
        finish(.failure(error ?? ReconnectError.unavailable))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, peripheral === self.peripheral else { return }
        recordStage("BLE 配件断开", detail: error.map { "\(($0 as NSError).domain) / \(($0 as NSError).code)" } ?? "none")
        finish(.failure(error ?? ReconnectError.unavailable))
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral, completion != nil else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            finish(.failure(error ?? ReconnectError.serviceMissing)); return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral, service.uuid == serviceID, completion != nil else { return }
        let expected = ["F6E14D01", "F6E14D02", "F6E14D03", "F6E14D04"].map {
            CBUUID(string: $0 + "-5D19-4CBD-A47D-19DBD8245E01")
        }
        let found = Set((service.characteristics ?? []).map(\.uuid))
        guard error == nil, expected.allSatisfy({ found.contains($0) }) else {
            finish(.failure(error ?? ReconnectError.serviceMissing)); return
        }
        recordStage("通知 GATT 服务已就绪", detail: "characteristics=\(found.count)")
        finish(.success(Evidence(ancsAuthorized: mode == .systemServices ? peripheral.ancsAuthorized : nil)))
    }
}
