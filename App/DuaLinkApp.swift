// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// The companion owns setup and consent. iOS owns notification delivery,
/// encryption, the three extensions, and execution of source notification actions.
@main
struct DuaLinkApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NotificationInteropView()
            }
        }
    }
}
