// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Preparation confirmations guide discovery; they are not Bluetooth telemetry.
@available(iOS 26.5, *)
struct NotificationInteropSetupSections: View {
    let model: NotificationInteropModel
    @AppStorage("interop.setup.pairingConfirmed") private var pairingConfirmed = false
    @AppStorage("interop.setup.harmonyPrepared") private var harmonyPrepared = false

    var body: some View {
        NotificationSetupStep(number: 1, title: "确认系统蓝牙配对", completed: pairingConfirmed) {
            if pairingConfirmed {
                Text("已由你确认。保留两台手机现有的配对。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("在两台手机的系统蓝牙设置中完成配对，并确认配对码一致。已经配对可直接继续。")
                    .font(.subheadline)
                DisclosureGroup("在哪里配对？") {
                    Text("iPhone：设置 → 蓝牙。\n鸿蒙：设置 → 星闪和蓝牙。\n从其中一端选择另一台手机，再分别确认。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("已完成系统配对") { pairingConfirmed = true }
            }
        }
        NotificationSetupStep(number: 2, title: "准备鸿蒙 DuaLink", completed: harmonyPrepared) {
            if harmonyPrepared {
                Text("已由你确认。首次添加时让鸿蒙 DuaLink 保持前台。")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("打开鸿蒙 DuaLink → 设置 → 消息模式，选择“通知回复”并点击连接按钮。两台手机模式必须一致。")
                    .font(.subheadline)
                Button("鸿蒙端已准备好") { harmonyPrepared = true }
                    .disabled(!pairingConfirmed)
            }
        }
        NotificationSetupStep(number: 3, title: "添加手机并授权", completed: false) {
            Text("选择同一台鸿蒙手机，再选择允许转发通知的 App。实时活动可在添加后单独开启。")
                .font(.subheadline)
            Text("实验功能兼容性：允许通知转发后，部分 iPhone 可能拒绝短信重新连接。若依赖短信同步，可先保留现有连接，暂不开启通知回复。")
                .font(.footnote).foregroundStyle(.secondary)
            Button("添加鸿蒙手机") { model.addAccessory(authorizeAfterAdding: true) }
                .disabled(!pairingConfirmed || !harmonyPrepared || !model.ready || model.busy)
        }
    }
}
