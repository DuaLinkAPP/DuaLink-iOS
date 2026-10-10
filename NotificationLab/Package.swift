// SPDX-License-Identifier: MPL-2.0
// swift-tools-version: 6.0
import PackageDescription

// 测试线协议、密钥编码和回复校验，不把主机单元测试误记为 iPhone 系统接口验证。
let package = Package(
    name: "DuaLinkNotificationLabCore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "NotificationLabCore", targets: ["NotificationLabCore"])],
    targets: [
        .target(name: "NotificationLabCore", path: "Shared", exclude: ["LabDiagnostics.swift"],
                sources: ["LabProtocol.swift", "LabBuildConfiguration.swift", "InteropMessageMode.swift", "InteropModeStore.swift", "LabMessageModeGate.swift", "LabFrameCodec.swift", "LabReceiveBuffer.swift", "LabSubscriptionState.swift", "LabResponseLedger.swift", "LabP256PublicKey.swift", "LabReconnectPolicy.swift", "LabLiveActivityPipeline.swift"]),
        .target(name: "NotificationInteropProductCore", path: "ProductCore"),
        .testTarget(name: "NotificationLabCoreTests", dependencies: ["NotificationLabCore", "NotificationInteropProductCore"], path: "Tests")
    ]
)
