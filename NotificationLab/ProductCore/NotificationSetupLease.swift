// SPDX-License-Identifier: MPL-2.0
import Foundation

/// Exclusive, temporary ownership of app-local Bluetooth discovery during ASK
/// setup. A busy owner can veto setup; no active device is forcibly disconnected.
@MainActor
final class NotificationSetupLease {
    static let shared = NotificationSetupLease()
    struct Owner {
        let pause: @MainActor () -> Bool
        let resume: @MainActor () -> Void
    }
    private var owners: [String: Owner] = [:]
    private var paused: [Owner] = []
    private(set) var isPreparing = false

    func register(_ name: String, pause: @escaping @MainActor () -> Bool,
                  resume: @escaping @MainActor () -> Void) {
        owners[name] = Owner(pause: pause, resume: resume)
    }

    func begin() -> Bool {
        guard !isPreparing else { return false }
        isPreparing = true
        for key in owners.keys.sorted() {
            guard let owner = owners[key] else { continue }
            guard owner.pause() else { end(); return false }
            paused.append(owner)
        }
        return true
    }

    func end() {
        guard isPreparing else { return }
        let pending = paused.reversed()
        paused.removeAll()
        isPreparing = false
        for owner in pending { owner.resume() }
    }
}
