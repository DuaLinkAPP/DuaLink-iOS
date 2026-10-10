// SPDX-License-Identifier: MPL-2.0
import Foundation

nonisolated struct InteropModeChoice: Codable, Equatable, Sendable {
    let version: Int
    let mode: InteropMessageMode
    let revision: UUID
    static let initial = InteropModeChoice(version: 1, mode: .sms,
        revision: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
}

/// Only the containing app writes the explicit choice; extensions read their App Group policy.
/// The revision prevents a quick reply → SMS → reply switch from reviving an obsolete session.
nonisolated struct InteropModeStore: Sendable {
    static var product: InteropModeStore { InteropModeStore(suiteName: LabBuildConfiguration.notificationAppGroup) }
    let suiteName: String
    private let key = "interop.messageMode.choice.v1"
    enum Failure: Error { case unavailable, readOnlyExtension }

    func read() -> InteropModeChoice {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: key), data.count <= 1024,
              let choice = try? JSONDecoder().decode(InteropModeChoice.self, from: data),
              choice.version == 1 else { return .initial }
        return choice
    }

    @discardableResult func select(_ mode: InteropMessageMode) throws -> InteropModeChoice {
        guard Bundle.main.bundleURL.pathExtension != "appex" else { throw Failure.readOnlyExtension }
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw Failure.unavailable }
        let current = read()
        guard current.mode != mode else { return current }
        let choice = InteropModeChoice(version: 1, mode: mode, revision: UUID())
        defaults.set(try JSONEncoder().encode(choice), forKey: key)
        return choice
    }

    func allowsNotifications(revision: UUID? = nil) -> Bool {
        let choice = read()
        return choice.mode == .notificationReply && (revision == nil || revision == choice.revision)
    }
}
