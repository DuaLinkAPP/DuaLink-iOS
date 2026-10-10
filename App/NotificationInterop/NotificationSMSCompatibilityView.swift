// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// This page manages the public forwarding permission only. The companion app
/// cannot read/remove iOS Bluetooth device tags or certify the MAP connection.
@available(iOS 26.5, *)
struct NotificationSMSCompatibilityView: View {
    let model: NotificationInteropModel

    var body: some View {
        List {
            Section {
                Label("短信与通知回复兼容性", systemImage: "message.badge.filled.fill")
                    .font(.headline)
                Text("已观察到部分 iPhone 在开启通知回复所需的系统转发后，拒绝重新建立短信连接。原短信连接可能暂时正常，重开鸿蒙 App 后才出现问题。")
                    .font(.subheadline)
            }

            Section {
                Text("如果鸿蒙提示 iPhone 拒绝短信访问，请保留当前配对。当前测试中，关闭通知转发也没有恢复短信，因此不建议为此关闭通知回复或反复重新配对。")
                    .font(.subheadline)
                Button("查看通知转发权限") {
                    guard let accessory = model.accessory else { return }
                    Task { await model.managePermissions(accessory) }
                }
                .disabled(!model.canManage || model.reconnecting)
                if model.permissionAction == .notifications {
                    ProgressView("正在打开通知转发设置…")
                }
                Text(model.notificationPermissionTitle)
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("保留当前设置")
            } footer: {
                Text("权限页面仅供核对，不是短信修复按钮。短信读取仍需保留蓝牙详情中的“显示信息通知”开启。")
            }

            Section("以鸿蒙短信结果为准") {
                Text("短信与通知回复在重新连接后的稳定并存问题仍在排查。请记录问题出现时间，并以鸿蒙短信页面能否重新读取内容为准。")
                Text("授权已允许、通知回复已连接，都不代表短信连接已恢复。")
            }
            .font(.subheadline)

            if let notice = model.notice {
                Section { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("短信连接受影响")
        .navigationBarTitleDisplayMode(.inline)
    }
}
