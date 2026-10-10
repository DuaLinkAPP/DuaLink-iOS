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
