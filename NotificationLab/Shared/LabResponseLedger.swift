// SPDX-License-Identifier: MPL-2.0
import Foundation

/// 一个会话内请求只执行一次；到达上限后拒绝新请求，而非淘汰旧 ID 导致重复执行。
nonisolated struct LabResponseLedger: Sendable {
    private(set) var results: [UUID: String] = [:]
    let capacity: Int

    init(capacity: Int = 256) { self.capacity = capacity }

    mutating func reserve(_ requestID: UUID) throws -> String? {
        if let previous = results[requestID] { return previous }
        guard results.count < capacity else { throw LabProtocolError.queueFull }
        results[requestID] = "pending"
        return nil
    }

    mutating func finish(_ requestID: UUID, result: String) {
        guard results[requestID] != nil else { return }
        results[requestID] = result
    }
}
