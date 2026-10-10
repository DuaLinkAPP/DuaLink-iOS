// SPDX-License-Identifier: MPL-2.0
import Foundation

extension LabAccessoryConnection {
    /// Receive inactivity is independent of connection/write deadlines. A write
    /// acknowledgement must not keep a truncated reply buffered indefinitely.
    func receive(_ bytes: Data) {
        guard LabMessageModeGate.permits(modeRevision) else { fail(.unavailable); return }
        guard !bytes.isEmpty else { return }
        do {
            let envelopes = try receiveBuffer.append(bytes)
            receiveDeadline?.cancel()
            receiveDeadline = nil
            if receiveBuffer.hasPendingFrame {
                let token = receiveBuffer.generation
                let item = DispatchWorkItem { [weak self] in
                    guard let self, !self.stopped, self.receiveBuffer.shouldExpire(token) else { return }
                    self.recordStage("BLE 回复分片接收超时")
                    self.fail(.timedOut)
                }
                receiveDeadline = item
                executor.asyncAfter(deadline: .now() + 15, execute: item)
            }
            for envelope in envelopes { onReceive?(envelope) }
        } catch {
            fail(.invalidFrame)
        }
    }

    func resetReceiveBuffer() {
        receiveDeadline?.cancel()
        receiveDeadline = nil
        receiveBuffer.reset()
    }
}
