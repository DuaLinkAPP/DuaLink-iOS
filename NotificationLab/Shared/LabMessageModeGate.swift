// SPDX-License-Identifier: MPL-2.0
import Foundation

/// The standalone developer lab retains its existing behavior. Shipping extensions follow the app's explicit switch.
nonisolated enum LabMessageModeGate {
    static var revision: UUID? {
        #if DUALINK_NOTIFICATIONS_PRODUCT
        InteropModeStore(suiteName: LabProtocol.appGroup).read().revision
        #else
        nil
        #endif
    }
    static var enabled: Bool {
        #if DUALINK_NOTIFICATIONS_PRODUCT
        InteropModeStore(suiteName: LabProtocol.appGroup).allowsNotifications()
        #else
        true
        #endif
    }
    static func permits(_ revision: UUID?) -> Bool {
        #if DUALINK_NOTIFICATIONS_PRODUCT
        guard let revision else { return false }
        return InteropModeStore(suiteName: LabProtocol.appGroup).allowsNotifications(revision: revision)
        #else
        return true
        #endif
    }
}
