// SPDX-License-Identifier: MPL-2.0
import CoreBluetooth
import Foundation
import OSLog

/// Reconnect only the ASK-authorized phone. Routine checks discover GATT only;
/// an explicit repair may ask the system to activate ANCS/classic profiles.
@MainActor
final class NotificationReconnectController: NSObject {
    struct Evidence { let ancsAuthorized: Bool? }
    typealias Completion = (Result<Evidence, Error>) -> Void
    let serviceID = CBUUID(string: "F6E14D00-5D19-4CBD-A47D-19DBD8245E01")
    var central: CBCentralManager?
    var peripheral: CBPeripheral?
    var target: UUID?
    var completion: Completion?
    var timeout: Task<Void, Never>?
    var mode: NotificationReconnectMode = .notificationService
    var connectStarted = false
    var targetPolicy: LabApprovedTargetPolicy?
    private let logger = Logger(subsystem: "ESP.DuaLink", category: "notification-connection")
    private var diagnosticStages: [[String: String]] = []
    var attemptID = UUID()
    var ancsAuthorizationChanged: ((Bool) -> Void)?

    func connect(to identifier: UUID, mode: NotificationReconnectMode = .notificationService,
                 ancsAuthorizationChanged: ((Bool) -> Void)? = nil,
                 completion: @escaping Completion) {
        guard self.completion == nil else { return }
        guard !NotificationSetupLease.shared.isPreparing else {
            completion(.failure(ReconnectError.setupInProgress)); return
        }
        // Retain this controller's existing lease for the same physical device.
        // There is no second central and no scan/connect race in repair mode.
        if target != identifier { stop() }
        target = identifier
        self.mode = mode
        self.ancsAuthorizationChanged = ancsAuthorizationChanged
        self.completion = completion
        connectStarted = false
        targetPolicy = LabApprovedTargetPolicy(approvedID: identifier)
        recordStage("已固定 ASK 授权目标", detail: "systemServices=\(mode == .systemServices)")
        let attempt = UUID()
        attemptID = attempt
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(25))
            guard !Task.isCancelled, let self, self.attemptID == attempt else { return }
            self.recordStage("连接阶段等待超时", detail: self.targetPolicy?.summary ?? "targetUnresolved")
            self.finish(.failure(ReconnectError.timedOut))
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            connectWhenReady()
        }
    }

    func stop() {
        if target != nil { recordStage("结束本地连接请求", detail: targetPolicy?.summary ?? "") }
        central?.stopScan()
        attemptID = UUID()
        connectStarted = false
        ancsAuthorizationChanged = nil
        timeout?.cancel(); timeout = nil
        let pending = completion
        completion = nil
        // Releasing this central's ownership does not cancel other clients' connections.
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral?.delegate = nil
        central?.delegate = nil
        peripheral = nil; central = nil; target = nil
        targetPolicy = nil
        pending?(.failure(CancellationError()))
    }

    func finish(_ result: Result<Evidence, Error>) {
        guard let callback = completion else { return }
        completion = nil
        timeout?.cancel(); timeout = nil
        central?.stopScan()
        // Keep our link while this page is present so pending system extension
        // work can resume. Leaving the page/removing the accessory releases it.
        if case .failure = result { stop() }
        callback(result)
    }

    func recordStage(_ event: String, detail: String = "") {
        let fingerprint = target.map(LabApprovedTargetPolicy.fingerprint) ?? "none"
        logger.info("\(event, privacy: .public), target=\(fingerprint, privacy: .public), \(detail, privacy: .public)")
        #if DEBUG
        diagnosticStages.append(["event": event, "target": fingerprint,
                                 "detail": detail, "date": Date().ISO8601Format()])
        if diagnosticStages.count > 20 { diagnosticStages.removeFirst(diagnosticStages.count - 20) }
        UserDefaults.standard.set(diagnosticStages, forKey: "interop.debug.connectionStages")
        #endif
    }

    enum ReconnectError: LocalizedError {
        case setupInProgress, unavailable, timedOut, serviceMissing
        var errorDescription: String? {
            switch self {
            case .setupInProgress: "配件设置正在进行，请完成后再重连。"
            case .unavailable: "蓝牙暂不可用，请确认蓝牙已开启且这台手机仍已配对。"
            case .timedOut: "重连超时，请让鸿蒙 DuaLink 保持前台，并确认通知回复已开启。"
            case .serviceMissing: "手机已连通，但通知回复服务未就绪，请检查鸿蒙的通知回复开关。"
            }
        }
    }
}
