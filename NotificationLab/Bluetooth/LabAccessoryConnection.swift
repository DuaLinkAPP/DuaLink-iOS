// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
@preconcurrency import CoreBluetooth
import Foundation

/// CoreBluetooth 与系统扩展的回调可能来自不同队列。
/// 所有可变状态及 BLE 对象都只在 executor 上访问；公开方法仅向该串行队列投递工作。
final class LabAccessoryConnection: NSObject, @unchecked Sendable {
    enum Channel: Sendable {
        case data, security
        var writeUUID: String { self == .data ? LabProtocol.dataToAccessory : LabProtocol.keyToAccessory }
        var notifyUUID: String { self == .data ? LabProtocol.dataFromAccessory : LabProtocol.keyFromAccessory }
    }
    typealias Completion = @Sendable (Result<Void, LabProtocolError>) -> Void
    struct PendingWrite {
        let bytes: Data
        let completion: Completion
        var offset = 0
    }

    let executor: DispatchQueue
    let channel: Channel
    let restoreIdentifier: String?
    var central: CBCentralManager?
    var accessorySession: ASAccessorySession?
    var approvedID: UUID?
    var peripheral: CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    var notifyCharacteristic: CBCharacteristic?
    var activeService: CBService?
    var receiveBuffer = LabReceiveBuffer()
    var receiveDeadline: DispatchWorkItem?
    var writes: [PendingWrite] = []
    var waitingForWrite = false
    var ready: Bool { subscription.isReady }
    var hasEstablishedConnection = false
    var stopped = false
    var deadline: DispatchWorkItem?
    var deadlineGeneration = 0
    var targetPolicy: LabApprovedTargetPolicy?
    var reconnectPolicy = LabReconnectPolicy()
    var subscription = LabSubscriptionState()
    var restoredPeripherals: [CBPeripheral] = []
    let modeRevision = LabMessageModeGate.revision
    var modeWatch: DispatchSourceTimer?
    var onReceive: (@Sendable (LabEnvelope) -> Void)?
    var onFailure: (@Sendable () -> Void)?

    init(channel: Channel, restoreIdentifier: String? = nil) {
        self.channel = channel
        self.restoreIdentifier = restoreIdentifier
        self.executor = DispatchQueue(label: "ESP.DuaLink.NotificationLab.\(channel)")
        super.init()
    }

    func start(onReceive: @escaping @Sendable (LabEnvelope) -> Void,
               onFailure: @escaping @Sendable () -> Void) {
        executor.async { [self] in
            self.onReceive = onReceive
            self.onFailure = onFailure
            guard LabMessageModeGate.permits(modeRevision) else { fail(.unavailable); return }
            watchMessageMode()
            let session = ASAccessorySession()
            accessorySession = session
            session.activate(on: executor) { [weak self] event in
                guard let self, !self.stopped else { return }
                self.recordStage("ASK 会话事件", detail: "type=\(event.eventType.rawValue), error=\(event.error.map { LabDiagnostics.errorCode($0) } ?? "none")")
                if event.eventType == .invalidated || event.error != nil {
                    self.fail(.unavailable); return
                }
                if [.activated, .accessoryAdded, .accessoryChanged, .accessoryRemoved].contains(event.eventType) {
                    let records = session.accessories.map {
                        LabAccessoryAuthorizationRecord(identifier: $0.bluetoothIdentifier, authorized: $0.state == .authorized)
                    }
                    switch LabAccessoryAuthorizationPolicy.select(records, boundID: self.approvedID) {
                    case .bind(let identifier):
                        self.approvedID = identifier
                        self.targetPolicy = LabApprovedTargetPolicy(approvedID: identifier)
                        self.recordStage("已固定 ASK 授权目标")
                        self.createCentralAfterAuthorization()
                        self.connectApprovedAccessory()
                    case .keep:
                        // A name or connection-state event must not create a
                        // second central or restart an already pending connect.
                        break
                    case .reject:
                        self.recordStage("ASK 授权目标已失效或变化", detail: "total=\(records.count), authorized=\(records.filter(\.authorized).count)")
                        self.fail(.unavailable)
                    }
                }
            }
            armDeadline(seconds: 20)
        }
    }

    func perform(_ operation: @escaping @Sendable () -> Void) { executor.async(execute: operation) }

    /// ASK must resolve this extension's approved accessory before CoreBluetooth
    /// is initialized. ASK can gate poweredOn independently of the physical radio.
    private func createCentralAfterAuthorization() {
        guard !stopped, approvedID != nil, central == nil else { return }
        var options: [String: Any] = [:]
        if let restoreIdentifier { options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier }
        recordStage("ASK 授权后创建 BLE 中央", detail: "authorization=\(CBManager.authorization.rawValue)")
        central = CBCentralManager(delegate: self, queue: executor, options: options)
    }

    // Called only from the connection executor; log state/counts, never device identifiers.
    func recordStage(_ event: String, detail: String = "") {
        let fingerprint = approvedID.map(LabApprovedTargetPolicy.fingerprint) ?? "none"
        LabDiagnostics.record(channel == .data ? "transport" : "security", event,
                              detail: "target=\(fingerprint), \(detail)")
    }

    /// 对单个完整信封给出一次结果；成功只表示 GATT 写入完成。
    func send(_ envelope: LabEnvelope, completion: @escaping Completion) {
        executor.async { [self] in
            guard !stopped, LabMessageModeGate.permits(modeRevision) else {
                completion(.failure(.unavailable)); fail(.unavailable); return
            }
            do {
                let bytes = try LabFrameCodec.encode(envelope)
                // Derive the remaining budget from the live queue; completion and
                // failure automatically release it without a separate stale counter.
                let pendingBytes = writes.reduce(0) { $0 + $1.bytes.count - $1.offset }
                guard LabProtocol.canQueueFrame(pendingFrames: writes.count, pendingBytes: pendingBytes,
                                                frameBytes: bytes.count) else {
                    recordStage("BLE 发送队列已满", detail: "frames=\(writes.count), remainingBytes=\(pendingBytes), incomingBytes=\(bytes.count)")
                    completion(.failure(.queueFull)); return
                }
                writes.append(PendingWrite(bytes: bytes, completion: completion))
                recordStage("BLE 消息已排队", detail: "frames=\(writes.count), remainingBytes=\(pendingBytes + bytes.count)")
                pumpWrites()
            } catch {
                completion(.failure(.frameTooLarge))
            }
        }
    }

    func stop() {
        executor.async { [self] in
            onFailure = nil
            fail(.unavailable)
        }
    }

    func connectApprovedAccessory() {
        guard LabMessageModeGate.permits(modeRevision) else { fail(.unavailable); return }
        guard !stopped, let central, central.state == .poweredOn,
              let approvedID, peripheral == nil else { return }
        let candidates = restoredPeripherals + central.retrievePeripherals(withIdentifiers: [approvedID])
        recordStage("检索已授权 BLE 配件", detail: "candidates=\(candidates.count), approvedMatches=\(candidates.filter { $0.identifier == approvedID }.count)")
        if let candidate = candidates.first(where: { $0.identifier == approvedID }) {
            let ownsRestoredConnection = restoredPeripherals.contains { $0 === candidate }
            if ownsRestoredConnection && candidate.state == .connected {
                peripheral = candidate
                candidate.delegate = self
                hasEstablishedConnection = true
                _ = targetPolicy?.confirmConnection(to: candidate.identifier)
                recordStage("恢复本地已有连接，发现服务")
                armDeadline(seconds: 20)
                candidate.discoverServices([CBUUID(string: LabProtocol.service)])
                return
            }
            submitApprovedConnection(candidate, source: "retrieved")
        }
        // Cached retrieval is not proof that the peer is currently visible.
        // Scan alongside the one pending connect; CoreBluetooth can refresh its
        // radio knowledge without cancelling/reissuing that pending request.
        startApprovedDiscovery()
    }

    func startApprovedDiscovery() {
        guard !stopped, let central, central.state == .poweredOn, approvedID != nil,
              !central.isScanning else { return }
        central.scanForPeripherals(withServices: [CBUUID(string: LabProtocol.service)])
        recordStage("开始扫描已登记目标的广播")
    }

    func submitApprovedConnection(_ candidate: CBPeripheral, source: String) {
        guard !stopped, let central, central.state == .poweredOn,
              targetPolicy?.submitConnection(to: candidate.identifier) == true else { return }
        peripheral = candidate
        candidate.delegate = self
        recordStage("提交已登记目标连接", detail: "source=\(source), peripheralState=\(candidate.state.rawValue)")
        central.connect(candidate)
    }

    func pumpWrites() {
        guard LabMessageModeGate.permits(modeRevision) else { fail(.unavailable); return }
        guard !stopped, ready, !waitingForWrite, !writes.isEmpty,
              let peripheral, let writeCharacteristic else { return }
        let maximum = peripheral.maximumWriteValueLength(for: .withResponse)
        guard maximum > 0 else { fail(.unavailable); return }
        let start = writes[0].offset
        let end = min(start + maximum, writes[0].bytes.count)
        let chunk = writes[0].bytes.subdata(in: start..<end)
        writes[0].offset = end
        waitingForWrite = true
        armDeadline(seconds: 10)
        peripheral.writeValue(chunk, for: writeCharacteristic, type: .withResponse)
    }

    func cancelDeadline() {
        deadlineGeneration += 1
        deadline?.cancel()
        deadline = nil
    }

    func armDeadline(seconds: TimeInterval) {
        cancelDeadline()
        let generation = deadlineGeneration
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, self.deadlineGeneration == generation else { return }
            self.recordStage("BLE 阶段等待超时", detail: self.targetPolicy?.summary ?? "ASKTargetUnresolved")
            self.fail(.timedOut)
        }
        deadline = item
        executor.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Local preference checks only; no radio heartbeat or keep-alive traffic.
    /// Event handlers also check the revision before every send, including while the extension is resumed.
    func watchMessageMode() {
        #if DUALINK_NOTIFICATIONS_PRODUCT
        let timer = DispatchSource.makeTimerSource(queue: executor)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self, !self.stopped else { return }
            if !LabMessageModeGate.permits(self.modeRevision) { self.fail(.unavailable) }
        }
        modeWatch = timer
        timer.resume()
        #endif
    }

    func fail(_ error: LabProtocolError) {
        guard !stopped else { return }
        stopped = true
        subscription.reset()
        modeWatch?.cancel()
        modeWatch = nil
        cancelDeadline()
        recordStage("结束本地连接请求", detail: targetPolicy?.summary ?? "ASKTargetUnresolved")
        central?.stopScan()
        let pending = writes
        writes.removeAll()
        waitingForWrite = false
        resetReceiveBuffer()
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        // Release only this connection's BLE objects. Keeping an obsolete manager
        // alive can compete with the next session's restoration identifier.
        peripheral?.delegate = nil
        restoredPeripherals.forEach { $0.delegate = nil }
        central?.delegate = nil
        peripheral = nil
        central = nil
        restoredPeripherals.removeAll()
        activeService = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        approvedID = nil
        targetPolicy = nil
        hasEstablishedConnection = false
        accessorySession?.invalidate()
        accessorySession = nil
        let failure = onFailure
        onFailure = nil
        onReceive = nil
        pending.forEach { $0.completion(.failure(error)) }
        LabDiagnostics.record(channel == .data ? "transport" : "security", "BLE 通道不可用", detail: error.rawValue)
        failure?()
    }
}
