// SPDX-License-Identifier: MPL-2.0
import SwiftUI

struct PrivacyDisclosureView: View {
    var body: some View {
        List {
            Section("通知与回复") {
                Text("仅处理你通过 iPhone 系统明确允许转发的通知和实时活动。通知由系统加密后发送到你授权的配件，回复由系统交给来源 App 执行。")
                Text("本项目没有开发者服务器、广告、分析 SDK 或账号登录。通知正文、回复文字和密钥不会上传到开发者服务。")
            }
            Section("本机保存") {
                Text("在本机保存功能开关、模式版本和设备显示名称。App 与扩展通过同一个 App Group 读取设置，不把第三方通知正文或回复文字保存在共享偏好中。")
                Text("系统配件登记和通知权限由 iOS 管理。取消配对可能影响使用同一系统蓝牙配对的其他功能。")
            }
            Section("诊断") {
                Text("连接阶段和错误码写入本机系统日志，开发构建可保存有限的阶段缓存。日志不记录通知正文、回复文字或密钥，也不会自动发送给开发者。")
            }
        }
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
