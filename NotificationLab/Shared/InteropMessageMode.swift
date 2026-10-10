// SPDX-License-Identifier: MPL-2.0
import Foundation

/// This app only opts into notification replies; SMS is the default/off state.
/// It never configures SMS or changes the mode selected on HarmonyOS.
nonisolated enum InteropMessageMode: String, Codable, CaseIterable, Sendable {
    case sms = "newSms"
    case notificationReply = "notificationReply"

    var title: String { self == .sms ? "短信模式" : "通知回复" }
    var detail: String {
        self == .sms ? "在鸿蒙查看和发送 iPhone 短信，不使用通知配件转发。" :
            "配合鸿蒙回复有效的消息通知，并按需使用实时活动。"
    }
}
