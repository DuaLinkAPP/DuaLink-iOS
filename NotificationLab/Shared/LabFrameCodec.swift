// SPDX-License-Identifier: MPL-2.0
import Foundation

/// TCP 式字节流分帧：4 字节大端长度 + JSON。支持 BLE 拆包、粘包和 UTF-8 边界。
nonisolated struct LabFrameCodec: Sendable {
    private var pending = Data()
    var hasPendingFrame: Bool { !pending.isEmpty }

    static func encode(_ envelope: LabEnvelope) throws -> Data {
        let json = try JSONEncoder().encode(envelope)
        guard json.count <= LabProtocol.maxFrameBytes else { throw LabProtocolError.frameTooLarge }
        let count = UInt32(json.count)
        var frame = Data([UInt8((count >> 24) & 255), UInt8((count >> 16) & 255),
                          UInt8((count >> 8) & 255), UInt8(count & 255)])
        frame.append(json)
        return frame
    }

    mutating func append(_ chunk: Data) throws -> [LabEnvelope] {
        guard chunk.count <= LabProtocol.maxFrameBytes + 4,
              pending.count + chunk.count <= 2 * (LabProtocol.maxFrameBytes + 4) else {
            pending.removeAll()
            throw LabProtocolError.frameTooLarge
        }
        pending.append(chunk)
        var result: [LabEnvelope] = []
        do {
            while pending.count >= 4 {
                let bytes = Array(pending.prefix(4))
                let length = bytes.reduce(0) { ($0 << 8) | Int($1) }
                guard length > 0, length <= LabProtocol.maxFrameBytes else {
                    throw LabProtocolError.invalidFrame
                }
                guard pending.count >= 4 + length else { break }
                let body = Data(pending.dropFirst(4).prefix(length))
                let envelope = try JSONDecoder().decode(LabEnvelope.self, from: body)
                guard envelope.version == LabProtocol.version else {
                    throw LabProtocolError.unsupportedVersion
                }
                pending = Data(pending.dropFirst(4 + length))
                result.append(envelope)
            }
            return result
        } catch {
            pending.removeAll()
            throw error
        }
    }
}
