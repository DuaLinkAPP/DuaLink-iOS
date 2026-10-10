// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Keeps incomplete inbound frames and their inactivity deadline in the same
/// generation. Old timeout callbacks cannot expire a new fragment or session.
nonisolated struct LabReceiveBuffer: Sendable {
    private var codec = LabFrameCodec()
    private(set) var generation: UInt64 = 0
    var hasPendingFrame: Bool { codec.hasPendingFrame }

    mutating func append(_ bytes: Data) throws -> [LabEnvelope] {
        // Empty updates are not progress and must not prolong a stalled frame.
        guard !bytes.isEmpty else { return [] }
        generation &+= 1
        return try codec.append(bytes)
    }

    func shouldExpire(_ token: UInt64) -> Bool {
        token == generation && hasPendingFrame
    }

    mutating func reset() {
        generation &+= 1
        codec = LabFrameCodec()
    }
}
