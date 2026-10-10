// SPDX-License-Identifier: MPL-2.0
import SwiftUI
import UIKit
import CoreBluetooth

@available(iOS 26.5, *)
struct NotificationInteropView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = NotificationInteropModel()

    var body: some View {
        List {
            NotificationMessageModeSection(model: model)
            if let notice = model.notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if model.messageMode == .notificationReply && !model.ready {
                        Button("重新检查") { model.start() }.disabled(model.busy)
                    }
                }
            }
            if model.messageMode == .notificationReply {
                NotificationInteropOverview(model: model)
                if model.accessories.isEmpty {
                    NotificationInteropSetupSections(model: model)
                } else {
                    if model.accessory != nil { NotificationInteropFeatureSections(model: model) }
                    NotificationConnectionSection(model: model)
                }
            }
            Section {
                NavigationLink {
                    NotificationInteropHelpView()
                } label: {
                    Label("连接与使用帮助", systemImage: "questionmark.circle")
                }
            } footer: {
                Text("短信在鸿蒙端操作即可。使用通知回复时，请确认鸿蒙已选择“通知回复”。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("通知回复")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { model.start() }
        .task {
            updateDebugWakeLock(scenePhase == .active)
            model.notificationPageAppeared(sceneActive: scenePhase == .active)
        }
        .onDisappear {
            model.notificationPageDisappeared()
            updateDebugWakeLock(false)
        }
        .onChange(of: scenePhase) { _, phase in
            updateDebugWakeLock(phase == .active)
            switch phase {
            case .active: model.notificationSceneBecameActive()
            case .inactive: model.notificationSceneBecameInactive()
            case .background: model.notificationSceneEnteredBackground()
            @unknown default: model.notificationSceneBecameInactive()
            }
        }
    }

    private func updateDebugWakeLock(_ active: Bool) {
        #if DEBUG
        // Explicit device-test launch only; normal launches retain auto-lock.
        if ProcessInfo.processInfo.arguments.contains("--notification-interop") {
            UIApplication.shared.isIdleTimerDisabled = active
        }
        #endif
    }
}
