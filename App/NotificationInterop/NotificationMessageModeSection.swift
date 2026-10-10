// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// SMS uses the existing system Bluetooth path; this app only opts into notification replies.
@available(iOS 26.5, *)
struct NotificationMessageModeSection: View {
    let model: NotificationInteropModel

    var body: some View {
        Section("短信模式说明") {
            Label("在鸿蒙端使用即可", systemImage: "message")
            Text("在鸿蒙 DuaLink 选择“短信模式”，查看或发送 iPhone 短信。iPhone 上的 DuaLink 无需任何操作。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        Section {
            Toggle("使用通知回复", isOn: Binding(
                get: { model.messageMode == .notificationReply },
                set: { model.selectMessageMode($0 ? .notificationReply : .sms) }
            ))
            Text("仅在鸿蒙也选择“通知回复”时开启。开启后，按下方步骤添加手机并允许通知转发；两端设置不匹配时，通知回复无法使用。")
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            Text("通知回复")
        } footer: {
            Text("实验功能：需要 iOS 26.5 或更高版本。正式使用时 iPhone 须位于欧盟，Apple 账户地区须为欧盟成员国。仅支持带回复操作的有效通知。")
        }
    }
}
