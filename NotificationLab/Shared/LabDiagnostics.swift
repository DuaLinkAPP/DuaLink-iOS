// SPDX-License-Identifier: MPL-2.0
import Foundation
import OSLog
#if DEBUG
import Synchronization
#endif

nonisolated struct LabDiagnostic: Codable, Sendable, Identifiable {
    let component: String
    let event: String
    let detail: String
    let date: Date
    var id: String { component }
}

/// 主 App 保存授权/测试结果；扩展写 OSLog，DEBUG 阶段另写自身缓存容器。
/// 不记录三方通知正文、回复文字或密钥。
nonisolated enum LabDiagnostics {
    static let components = ["setup", "authorization", "fixture", "activityAuthorization", "activityFixture"]
    private static let logger = Logger(subsystem: "ESP.DuaLink.NotificationLab", category: "stages")

    static func record(_ component: String, _ event: String, detail: String = "") {
        logger.notice("pid=\(ProcessInfo.processInfo.processIdentifier) \(component, privacy: .public): \(event, privacy: .public) \(detail, privacy: .public)")
        // AccessoryDataProvider's App Group is read-only. Use the same logging
        // boundary for every extension; a missing preference is not runtime proof.
        guard Bundle.main.bundleURL.pathExtension != "appex" else {
            #if DEBUG
            recordExtensionCache(component, event, detail: detail)
            #endif
            return
        }
        let item = LabDiagnostic(component: component, event: event, detail: detail, date: Date())
        if let data = try? JSONEncoder().encode(item) {
            UserDefaults(suiteName: LabProtocol.appGroup)?.set(data, forKey: "lab.\(component)")
        }
    }

    static func read() -> [LabDiagnostic] {
        let defaults = UserDefaults(suiteName: LabProtocol.appGroup)
        return components.compactMap { component in
            guard let data = defaults?.data(forKey: "lab.\(component)") else { return nil }
            return try? JSONDecoder().decode(LabDiagnostic.self, from: data)
        }.sorted { $0.date > $1.date }
    }

    static func errorCode(_ error: any Error) -> String {
        let error = error as NSError
        return "\(error.domain) / \(error.code)"
    }

    #if DEBUG
    private struct ProcessStage: Codable, Sendable {
        let component: String
        let event: String
        let detail: String
        let date: Date
        let pid: Int32
    }
    private static let cacheStages = Mutex<[ProcessStage]>([])

    /// Developer-tool diagnostics stay in this extension's own writable Caches
    /// directory. The shared App Group is never used for extension output.
    private static func recordExtensionCache(_ component: String, _ event: String, detail: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let item = ProcessStage(component: String(component.prefix(64)), event: String(event.prefix(256)),
                                detail: String(detail.prefix(1024)), date: Date(), pid: pid)
        cacheStages.withLock { stages in
            stages.append(item)
            if stages.count > 64 { stages.removeFirst(stages.count - 64) }
            do {
                let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
                let directory = caches.appendingPathComponent("DuaLinkLabStages", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(stages)
                // Keep the lock through replacement so concurrent callbacks cannot
                // overwrite a newer snapshot with an older one.
                try data.write(to: directory.appendingPathComponent("\(pid).json"), options: .atomic)
            } catch {
                logger.error("pid=\(pid) extension stage cache failed: \(errorCode(error), privacy: .public)")
            }
        }
    }
    #endif
}
