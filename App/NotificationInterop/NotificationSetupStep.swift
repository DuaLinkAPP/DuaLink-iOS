// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Shared numbered card used by the live setup flow and its tutorial.
struct NotificationSetupStep<Content: View>: View {
    let number: Int
    let title: String
    let completed: Bool
    @ViewBuilder var content: Content

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: completed ? "checkmark.circle.fill" : "\(number).circle.fill")
                    .foregroundStyle(completed ? .green : .blue).font(.title3)
                Text(title).font(.headline)
            }.padding(.vertical, 3)
            content
        }
    }
}
