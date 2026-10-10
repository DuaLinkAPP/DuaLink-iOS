// SPDX-License-Identifier: MPL-2.0
import Testing
@testable import NotificationLabCore

@Test func eachDeveloperCanSupplyTheirOwnSharedGroup() {
    let info = ["DuaLinkNotificationAppGroup": "group.com.example.companion.notifications"]
    #expect(LabBuildConfiguration.appGroup(from: info) == "group.com.example.companion.notifications")
}

@Test(arguments: ["", "$(UNRESOLVED_GROUP)", "group.com.example with spaces", "com.example.not-a-group"])
func invalidGroupConfigurationNeverUsesUnexpandedBuildVariables(value: String) {
    let info = ["DuaLinkNotificationAppGroup": value]
    #expect(LabBuildConfiguration.appGroup(from: info) == "group.org.dualink.opensource.notifications")
}
