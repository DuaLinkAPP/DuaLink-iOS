// SPDX-License-Identifier: MPL-2.0
import SwiftUI

/// Registration and permission never imply a currently connected data channel.
@available(iOS 26.5, *)
struct NotificationInteropOverview: View {
    let model: NotificationInteropModel

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: model.accessories.isEmpty ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 64)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DuaLink").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var title: String {
        if let accessory = model.accessory { return model.deviceName(for: accessory) }
        return model.accessories.isEmpty ? "连接你的鸿蒙手机" : "需要确认接收设备"
    }

    private var subtitle: String {
        if model.accessory != nil { return "手机已添加 · 通知与实时活动分开授权" }
        if model.accessories.isEmpty { return "在鸿蒙查看 iPhone 通知，体验通知回复与实时活动实验功能。" }
        return "发现多条设备登记。请在设备管理中核对正在使用的手机。"
    }
}

@available(iOS 26.5, *)
struct NotificationInteropFeatureSections: View {
    let model: NotificationInteropModel

    var body: some View {
        Section {
            featureHeading("通知与回复", symbol: "bubble.left.and.bubble.right.fill", color: .blue)
            permissionRow(model.notificationPermissionTitle, state: model.notificationPermission)
            Text("请在鸿蒙也选择“通知回复”。此模式不提供主动发短信；短信在鸿蒙端选择“短信模式”使用，iPhone 上的 DuaLink 无需操作。")
                .font(.footnote).foregroundStyle(.secondary)
            Button(model.notificationPrimaryAction) {
                Task { await model.performPrimaryAction() }
            }
            .disabled(!model.canManage)
            if model.permissionAction == .notifications { ProgressView("正在打开通知设置…").font(.subheadline) }
            NavigationLink("短信连接受影响？") {
                NotificationSMSCompatibilityView(model: model)
            }
        } footer: {
            Text("实验功能可能因系统条件或来源 App 而无法生效。只有来源 App 提供回复操作时，才会显示回复入口。")
        }
        Section {
            featureHeading("实时活动", symbol: "rectangle.on.rectangle", color: .teal)
            permissionRow(model.liveActivityPermissionTitle, state: model.liveActivityPermission)
            Button("管理实时活动权限") {
                Task { await model.manageLiveActivities() }
            }
            .disabled(!model.canManage)
            if model.permissionAction == .liveActivities { ProgressView("正在打开实时活动设置…").font(.subheadline) }
        } footer: {
            Text("实验功能：部分 App 的实时活动可能无法同步。成功接收后，可在鸿蒙页面和桌面卡片查看；卡片每次展示一个活动，支持自动切换和手动翻页。")
        }
    }

    private func featureHeading(_ title: String, symbol: String, color: Color) -> some View {
        Label {
            HStack(spacing: 8) {
                Text(title).font(.headline)
                Text("实验功能")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .padding(.vertical, 2)
    }

    private func permissionRow(_ title: String, state: NotificationPermissionState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: state.currentlyPermitted ? "checkmark.shield" : "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(state.currentlyPermitted ? Color.primary : Color.secondary)
            if state.queryFailed && state.confirmed == nil {
                Text("暂未读取到系统权限；可在管理权限中确认。读取失败不会关闭已有转发。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
