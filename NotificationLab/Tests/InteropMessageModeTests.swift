// SPDX-License-Identifier: MPL-2.0
import Foundation
import Testing
@testable import NotificationLabCore

private func withModeStore(_ run: (InteropModeStore, String) throws -> Void) rethrows {
    let suite = "DuaLinkModeTests.\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    try run(InteropModeStore(suiteName: suite), suite)
}

@Test func existingInstallWithoutExplicitReplyChoiceRemainsOff() throws {
    withModeStore { store, suite in
        UserDefaults(suiteName: suite)?.set(true, forKey: "interop.oldNotificationPermission")
        #expect(store.read().mode == .sms)
        #expect(!store.allowsNotifications())
    }
}

@Test func explicitReplyChoiceIsVisibleToAnotherReaderAndSurvivesRelaunch() throws {
    try withModeStore { store, suite in
        let choice = try store.select(.notificationReply)
        let extensionReader = InteropModeStore(suiteName: suite)
        #expect(extensionReader.read() == choice)
        #expect(extensionReader.allowsNotifications(revision: choice.revision))
    }
}

@Test func switchingOffInvalidatesPreviouslyQueuedSessionEvenAfterSwitchingOnAgain() throws {
    try withModeStore { store, _ in
        let old = try store.select(.notificationReply)
        try store.select(.sms)
        #expect(!store.allowsNotifications(revision: old.revision))
        let current = try store.select(.notificationReply)
        #expect(current.revision != old.revision)
        #expect(!store.allowsNotifications(revision: old.revision))
        #expect(store.allowsNotifications(revision: current.revision))
    }
}

@Test func repeatingTheSameChoiceDoesNotCancelAHealthySession() throws {
    try withModeStore { store, _ in
        let first = try store.select(.notificationReply)
        let repeated = try store.select(.notificationReply)
        #expect(first == repeated)
    }
}

@Test func malformedSharedPreferenceCannotEnableNotificationForwarding() throws {
    withModeStore { store, suite in
        UserDefaults(suiteName: suite)?.set(Data("{\"version\":99,\"mode\":\"notificationReply\"}".utf8),
                                             forKey: "interop.messageMode.choice.v1")
        #expect(!store.allowsNotifications())
        #expect(store.read().mode == .sms)
    }
}
