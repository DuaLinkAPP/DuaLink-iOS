// SPDX-License-Identifier: MPL-2.0
import Foundation
import CryptoKit

/// Bound recovery without depending on a timer in a suspendable extension.
/// Only frames that have never reached CoreBluetooth may survive a reconnect.
nonisolated struct LabReconnectPolicy: Sendable {
    private(set) var attempts = 0
    private(set) var waitingForProfileDisconnect = false
    private var profileRecoveryAttempted = false

    static func canResume(writeOffsets: [Int], waitingForWrite: Bool, hasPendingReceive: Bool = false) -> Bool {
        !hasPendingReceive && !waitingForWrite && writeOffsets.allSatisfy { $0 == 0 }
    }

    mutating func beginRecovery(writeOffsets: [Int], waitingForWrite: Bool, hasPendingReceive: Bool = false) -> Bool {
        guard Self.canResume(writeOffsets: writeOffsets, waitingForWrite: waitingForWrite, hasPendingReceive: hasPendingReceive) else { return false }
        // The profile recovery reserved its one attempt before cancelling our
        // local connection. didDisconnect must not charge the same attempt twice.
        if waitingForProfileDisconnect {
            waitingForProfileDisconnect = false
            return true
        }
        guard attempts < 3 else { return false }
        attempts += 1
        return true
    }

    mutating func beginProfileRecovery(writeOffsets: [Int], waitingForWrite: Bool, hasPendingReceive: Bool = false) -> Bool {
        guard !profileRecoveryAttempted, attempts < 3,
              Self.canResume(writeOffsets: writeOffsets, waitingForWrite: waitingForWrite, hasPendingReceive: hasPendingReceive) else { return false }
        attempts += 1
        profileRecoveryAttempted = true
        waitingForProfileDisconnect = true
        return true
    }

    mutating func didDeliverFrame() {
        attempts = 0
        profileRecoveryAttempted = false
        waitingForProfileDisconnect = false
    }
}

/// Discovery can refresh radio visibility, but it can never select another peer
/// or submit a second connect while CoreBluetooth owns the first request.
nonisolated struct LabApprovedTargetPolicy: Sendable {
    let approvedID: UUID
    private(set) var advertisementSeen = false
    private(set) var connectSubmitted = false
    private(set) var connectionConfirmed = false

    mutating func observeAdvertisement(from identifier: UUID) -> Bool {
        guard identifier == approvedID else { return false }
        advertisementSeen = true
        return true
    }

    mutating func submitConnection(to identifier: UUID) -> Bool {
        guard identifier == approvedID, !connectSubmitted, !connectionConfirmed else { return false }
        connectSubmitted = true
        return true
    }

    mutating func confirmConnection(to identifier: UUID) -> Bool {
        guard identifier == approvedID else { return false }
        connectionConfirmed = true
        return true
    }

    var summary: String {
        "advertisementSeen=\(advertisementSeen), connectSubmitted=\(connectSubmitted), didConnect=\(connectionConfirmed)"
    }

    /// A stable pseudonym lets the app/security/transport logs be compared
    /// without recording the high-entropy CoreBluetooth identifier itself.
    static func fingerprint(_ identifier: UUID) -> String {
        let bytes = Data("DuaLink approved target v1:\(identifier.uuidString.uppercased())".utf8)
        return SHA256.hash(data: bytes).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// Snapshot values rather than retaining a mutable ASAccessory object. The same
/// Bluetooth identifier can change authorization during a system re-pair.
nonisolated struct LabAccessoryAuthorizationRecord: Equatable, Sendable {
    let identifier: UUID?
    let authorized: Bool
}

nonisolated enum LabAccessoryAuthorizationPolicy {
    enum Boundary: Equatable, Sendable { case unchanged, identityChanged, authorizationChanged }
    enum Selection: Equatable, Sendable { case bind(UUID), keep, reject }

    static func boundary(previous: LabAccessoryAuthorizationRecord?,
                         current: LabAccessoryAuthorizationRecord) -> Boundary {
        guard let previous, previous.identifier == current.identifier else { return .identityChanged }
        return previous.authorized == current.authorized ? .unchanged : .authorizationChanged
    }

    /// Revalidate a bound connection, never silently move it to another device.
    /// Unrelated unapproved records do not replace the unique authorized peer.
    static func select(_ records: [LabAccessoryAuthorizationRecord], boundID: UUID?) -> Selection {
        let authorized = records.filter(\.authorized)
        guard authorized.count == 1, let identifier = authorized.first?.identifier else { return .reject }
        guard let boundID else { return .bind(identifier) }
        return boundID == identifier ? .keep : .reject
    }
}
