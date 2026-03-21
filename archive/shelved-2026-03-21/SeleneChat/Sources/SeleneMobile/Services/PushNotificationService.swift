import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UserNotifications

@MainActor
class PushNotificationService: NSObject, ObservableObject {
    @Published var isRegistered = false
    @Published var permissionStatus: UNAuthorizationStatus = .notDetermined

    /// Remote push notifications require a paid Apple Developer account with APS entitlement.
    /// Set to false for free developer accounts to avoid failed registration attempts.
    var remoteNotificationsEnabled = false

    private var serverURL: String = ""
    private var apiToken: String = ""

    func configure(serverURL: String, apiToken: String) {
        self.serverURL = serverURL
        self.apiToken = apiToken
    }

    func requestPermission() {
        #if os(iOS)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { [weak self] granted, _ in
            Task { @MainActor in
                guard let self else { return }
                if granted && self.remoteNotificationsEnabled {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                self.checkPermissionStatus()
            }
        }
        #endif
    }

    func checkPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.permissionStatus = settings.authorizationStatus
            }
        }
    }

    func registerDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()

        guard !serverURL.isEmpty else { return }

        Task {
            do {
                guard let url = URL(string: "\(serverURL)/api/devices/register") else { return }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !apiToken.isEmpty {
                    request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                }

                struct Body: Encodable { let token: String; let platform: String }
                request.httpBody = try JSONEncoder().encode(Body(token: token, platform: "ios"))

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    isRegistered = true
                }
            } catch {
                // Silently fail - will retry next app launch
            }
        }
    }

    /// Handle notification tap — returns the notification type and data for routing
    func handleNotificationResponse(_ response: UNNotificationResponse) -> NotificationAction? {
        let userInfo = response.notification.request.content.userInfo

        guard let type = userInfo["type"] as? String else { return nil }

        switch type {
        case "briefing":
            return .openBriefing
        case "thread":
            let threadName = userInfo["threadName"] as? String
            return .openThread(name: threadName)
        default:
            return nil
        }
    }

    enum NotificationAction {
        case openBriefing
        case openThread(name: String?)
    }
}
