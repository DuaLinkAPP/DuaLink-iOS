// SPDX-License-Identifier: MPL-2.0
/// One handshake per connection/service generation. Sending a new batch must
/// never toggle the subscription: incoming replies can overlap outgoing data.
nonisolated struct LabSubscriptionState: Sendable {
    enum Action: Equatable, Sendable { case none, disable, enable, ready, lost }
    private enum Phase: Sendable { case idle, disabling, enabling, ready }
    private var phase: Phase = .idle
    var isReady: Bool { phase == .ready }
    var hasStarted: Bool { phase != .idle }

    mutating func prepare(isData: Bool, isNotifying: Bool) -> Action {
        guard phase == .idle else { return .none }
        // A restored data characteristic can retain stale CCCD state after the
        // peer restarts. Refresh it only before this generation begins sending.
        if isData && isNotifying {
            phase = .disabling
            return .disable
        }
        phase = .enabling
        return .enable
    }

    mutating func observed(isNotifying: Bool) -> Action {
        switch phase {
        case .idle: return .none
        case .disabling:
            guard !isNotifying else { return .none }
            phase = .enabling
            return .enable
        case .enabling:
            guard isNotifying else { return .none }
            phase = .ready
            return .ready
        case .ready:
            // A repeated success callback must not cancel an active write timeout.
            return isNotifying ? .none : .lost
        }
    }

    mutating func reset() { phase = .idle }
}

/// Read the standard CCCD before an idle outgoing data batch. A read does not
/// interrupt inbound replies; only a confirmed remote unsubscribe permits renewal.
nonisolated struct LabSubscriptionProbe: Sendable {
    enum Result: Equatable, Sendable { case subscribed, renew, invalid }
    private(set) var pending = false

    mutating func begin(isData: Bool, ready: Bool, queueEmpty: Bool, writing: Bool) -> Bool {
        guard isData, ready, queueEmpty, !writing, !pending else { return false }
        pending = true
        return true
    }

    mutating func complete(_ value: Int) -> Result {
        guard pending else { return .invalid }
        pending = false
        guard (0...3).contains(value) else { return .invalid }
        return value == 0 ? .renew : .subscribed
    }

    mutating func reset() { pending = false }
}
