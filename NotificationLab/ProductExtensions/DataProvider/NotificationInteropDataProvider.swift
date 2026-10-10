// SPDX-License-Identifier: MPL-2.0
import AccessoryNotifications
import AccessoryLiveActivities
import AccessoryTransportExtension
import ExtensionFoundation

/// Both features use the already-authorized accessory and encrypted transport.
@main
struct NotificationInteropDataProvider: AccessoryDataProvider {
    var extensionPoint: AppExtensionPoint {
        Identifier("com.apple.accessory-data-provider")
        Implementing {
            NotificationsForwarding { NotificationForwardingHandler() }
            LiveActivityForwarding { LiveActivityForwardingHandler() }
        }
    }
}
