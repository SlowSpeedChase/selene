import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

class MobileAppDelegate: NSObject {
    var pushService: PushNotificationService?
}

#if os(iOS)
extension MobileAppDelegate: UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            pushService?.registerDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Silently handle - push is optional
    }
}
#endif

extension MobileAppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .badge, .sound]
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        _ = await MainActor.run {
            pushService?.handleNotificationResponse(response)
        }
        // Navigation handling will be added when tab routing is implemented
    }
}
