// SPDX-License-Identifier: MPL-2.0
import CoreBluetooth
import Foundation
import Testing
@testable import NotificationInteropProductCore

@Test func connectionTimeoutUsesActionableChineseInsteadOfSystemEnglish() {
    let error = NSError(domain: CBErrorDomain, code: CBError.Code.connectionTimeout.rawValue,
                        userInfo: [NSLocalizedDescriptionKey: "The connection has timed out unexpectedly."])
    #expect(NotificationConnectionNotice.systemFailure(error) == NotificationConnectionNotice.message(for: .timedOut))
    #expect(NotificationConnectionNotice.systemFailure(error).contains("两端都选择“通知回复”"))
}

@Test func errorCodeFromAnotherDomainNeverMisclassifiesPairing() {
    let error = NSError(domain: "UnrelatedDomain", code: CBError.Code.peerRemovedPairingInformation.rawValue)
    #expect(NotificationConnectionNotice.systemFailure(error) == NotificationConnectionNotice.message(for: .unknown))
}

@Test func bluetoothFailuresKeepTheirDifferentRecoveryAdvice() {
    let cases: [(CBError.Code, NotificationConnectionNotice.Reason)] = [
        (.peripheralDisconnected, .disconnected), (.notConnected, .disconnected),
        (.encryptionTimedOut, .encryptionTimedOut), (.peerRemovedPairingInformation, .pairingChanged),
        (.operationCancelled, .cancelled)
    ]
    for (code, reason) in cases {
        let error = NSError(domain: CBErrorDomain, code: code.rawValue)
        #expect(NotificationConnectionNotice.systemFailure(error) == NotificationConnectionNotice.message(for: reason))
    }
}

@Test func serviceDiscoverySuccessDoesNotClaimForwardingOrReplySucceeded() {
    #expect(NotificationConnectionNotice.serviceFound.contains("已找到鸿蒙通知服务"))
    #expect(NotificationConnectionNotice.serviceFound.contains("尚未确认回复通道"))
    #expect(!NotificationConnectionNotice.serviceFound.contains("回复服务可用"))
    #expect(!NotificationConnectionNotice.serviceFound.contains("转发成功"))
}

@Test func ordinaryConnectionCheckNeverRequestsSystemProfileChanges() {
    let mode = NotificationReconnectMode.notificationService
    #expect(mode.options(ancsKey: "ANCS", bridgingKey: "Classic").isEmpty)
    #expect(!mode.requestsANCS)
    #expect(!mode.enablesTransportBridging)
}

@Test func explicitSystemRepairRequestsOnlyANCSAndClassicBridging() {
    let mode = NotificationReconnectMode.systemServices
    #expect(mode.requestsANCS)
    #expect(mode.enablesTransportBridging)
    let options = mode.options(ancsKey: "ANCS", bridgingKey: "Classic")
    #expect(options.count == 2)
    #expect(options["ANCS"] == true)
    #expect(options["Classic"] == true)
}

@Test func systemConnectionEvidenceKeepsANCSAndForwardingSeparate() {
    let allowed = NotificationConnectionNotice.systemServicesFound(ancsAuthorized: true)
    let notAllowed = NotificationConnectionNotice.systemServicesFound(ancsAuthorized: false)
    #expect(allowed.contains("系统通知共享已允许"))
    #expect(notAllowed.contains("系统通知共享尚未允许"))
    #expect(allowed.contains("通知转发权限会单独检查"))
    #expect(!allowed.contains("已允许通知转发"))
}
