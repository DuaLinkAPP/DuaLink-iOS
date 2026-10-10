// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct NotificationInteropHelpView: View {
    var body: some View {
        List {
            Section("短信无需设置本 App") {
                helpText("在鸿蒙 DuaLink 选择“短信模式”。短信功能在鸿蒙端使用，iPhone 上的 DuaLink 无需任何操作。系统蓝牙配对和信息访问授权仍由 iPhone 系统管理。")
            }
            Section("日常使用") {
                DisclosureGroup("如何回复 iPhone 通知？") {
                    helpText("打开鸿蒙 DuaLink 的通知列表，左滑通知选择“回复”，输入文字后发送。只有来源 App 提供回复操作时才会显示入口；通知没有回复操作时，仍可查看内容。")
                    helpText("删除支持系统关闭操作的通知，会请求 iPhone 同步处理；否则只从鸿蒙列表移除。")
                }
                DisclosureGroup("如何查看实时活动？") {
                    helpText("先在 iPhone 的“管理实时活动权限”中允许相应 App，再打开鸿蒙 DuaLink 的实时活动开关。来源 App 产生新的活动后，会显示在鸿蒙实时活动页。")
                    helpText("可将 DuaLink 实时活动卡片添加到鸿蒙桌面。每张卡片一次展示一个活动，用左右按钮翻页；某个活动更新时，会自动展示该活动。")
                    helpText("展示内容取决于来源 App 提供的状态和提醒。部分更新只包含状态，不包含新文字。")
                }
                DisclosureGroup("通知、短信和电话有什么区别？") {
                    helpText("这里只管理通知回复与实时活动。短信在鸿蒙端操作，iPhone 上的 DuaLink 无需设置短信模式。")
                    helpText("它们共用系统蓝牙配对，不能保证互不影响。已观察到开启新通知转发后，iPhone 拒绝短信重新连接。")
                }
            }
            Section("遇到问题") {
                DisclosureGroup("开启通知回复后，短信为什么被拒绝？") {
                    helpText("部分 iPhone 会在新通知转发配置后限制短信连接。旧短信会话可能仍可用，重开鸿蒙 App 后才暴露问题。")
                    helpText("在通知回复页面选择“短信连接受影响？”查看说明。当前测试中，关闭转发也没有恢复短信，请保留配对和所需权限，避免反复重试或重新配对。")
                }
                DisclosureGroup("已授权，为什么没有收到内容？") {
                    helpText("授权只决定哪些 App 可以转发。请检查鸿蒙 DuaLink 中的连接状态，并确认 iPhone 实际产生了新的系统通知或实时活动提醒。只在来源 App 内看到消息，不一定会产生系统通知。")
                    helpText("通知权限与实时活动权限分别设置，请检查相应 App 是否在允许列表内。")
                }
                DisclosureGroup("连接中断了怎么办？") {
                    helpText("让两台手机靠近并保持蓝牙开启，在鸿蒙 DuaLink 选择“通知回复”并开始连接，再回到本页点“重新连接”。正在恢复时请稍等，避免反复切换开关。")
                    helpText("重新连接会检查已授权手机的接收服务，保留现有配对。回复和活动是否恢复，请以鸿蒙状态及新内容能否到达为准。")
                }
                DisclosureGroup("可以修改手机名称吗？") {
                    helpText("在“设备管理”中选择“修改系统显示名称”。如果没有该选项，也可在 iPhone 设置 → 蓝牙 → 设备详情中修改名称，无需取消配对。")
                }
                DisclosureGroup("什么时候需要取消配对？") {
                    helpText("仅在不再使用这台设备或明确需要重新配置时取消配对。此操作会停止转发，也可能中断原通知、短信和电话连接。临时连接问题请先尝试重新连接。")
                }
            }
            Section {
                DisclosureGroup("查看首次连接步骤") {
                    setupStep("1. 系统蓝牙配对", detail: "在两台手机的系统蓝牙设置中选择对方，确认配对码。已有配对无需重做。")
                    setupStep("2. 准备鸿蒙 DuaLink", detail: "进入设置 → 消息模式，选择“通知回复”并点击连接按钮。首次添加时保持应用前台。")
                    setupStep("3. 添加手机并授权", detail: "回到 iPhone DuaLink 的通知回复页面，开启“使用通知回复”，添加同一台鸿蒙手机并允许通知转发。需要实时活动时，再单独管理实时活动权限。")
                }

            } header: {
                Text("连接准备")
            }
            Section {
                NavigationLink("隐私说明") { PrivacyDisclosureView() }
            }
            Section("使用条件") {
                helpText("通知回复与实时活动转发需要 iPhone 和 iOS 26.5 或更高版本。正式安装还受 Apple 的设备所在地区和 Apple 账户地区条件限制；开发测试条件不同。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("连接与使用帮助")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpText(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 3)
    }

    private func setupStep(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium))
            helpText(detail)
        }
        .padding(.vertical, 4)
    }
}
