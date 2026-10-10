// SPDX-License-Identifier: MPL-2.0
import AccessorySetupKit
import SwiftUI

/// Removal always targets the accessory that appeared in the confirmation sheet.
@available(iOS 26.5, *)
struct NotificationConnectionSection: View {
    let model: NotificationInteropModel
    @State private var removalTarget: ASAccessory?
    @State private var showsRemovalConfirmation = false
    @State private var showsDeviceManagement = false

    var body: some View {
        Section {
            if model.accessory != nil {
                Button {
                    model.reconnect()
                } label: {
                    Label(model.reconnecting ? "正在检查连接…" : "重新连接", systemImage: "arrow.clockwise")
                }
                .disabled(!model.canManage || model.reconnecting)
            }
            if model.accessory != nil {
                DisclosureGroup("系统连接恢复") {
                    Button {
                        model.restoreSystemConnection()
                    } label: {
                        Label(model.reconnecting && model.reconnectMode == .systemServices ? "正在恢复系统连接…" : "恢复系统连接",
                              systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(!model.canManage || model.reconnecting)
                    Text("检查已登记手机的系统蓝牙服务，保留现有配对。此操作不能解除 iPhone 对短信访问的拒绝；短信被拒绝时，请查看“短信连接受影响？”中的兼容性说明。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let result = model.connectionNotice {
                Text(result).font(.footnote).foregroundStyle(.secondary)
            }
            Button("刷新授权状态") { model.start() }
                .disabled(model.busy || model.accessory == nil)
        } header: {
            Text("连接检查")
        } footer: {
            Text("已添加手机或允许转发，不代表同步通道已就绪。连接结果和内容是否到达，请同时查看鸿蒙端状态。")
        }
        Section {
            DisclosureGroup("设备管理", isExpanded: $showsDeviceManagement) {
                ForEach(model.accessories, id: \.self) { accessory in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.deviceName(for: accessory)).font(.subheadline.weight(.medium))
                        Text("已登记的接收设备").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.accessories.count == 1,
                       accessory.displayName != model.deviceName(for: accessory) {
                        Button("修改系统显示名称") { model.renameSystemAccessory() }
                            .disabled(!model.canManage)
                    }
                    Button(model.accessories.count == 1 ? "取消配对" : "取消与 \(model.deviceName(for: accessory)) 的配对",
                           role: .destructive) {
                        removalTarget = accessory
                        showsRemovalConfirmation = true
                    }
                    .disabled(!model.ready || model.busy)
                }
            }
        }
        .alert("取消与这台手机的配对？", isPresented: $showsRemovalConfirmation) {
            Button("取消配对", role: .destructive) {
                if let target = removalTarget { model.removeAccessory(target) }
                removalTarget = nil
            }
            Button("保留配对", role: .cancel) { removalTarget = nil }
        } message: {
            Text("将移除“\(removalTarget.map { model.deviceName(for: $0) } ?? "这台手机")”的配件登记并停止通知转发，系统配对、原通知、短信和电话连接也可能中断。再次使用需重新配对和授权。连接异常时请先尝试“重新连接”。")
        }
    }
}
