import SwiftUI
import SeleneShared
import UserNotifications

@main
struct SeleneMobileApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) var appDelegate
    #endif
    @StateObject private var connectionManager = ConnectionManager()
    @StateObject private var pushService = PushNotificationService()

    var body: some Scene {
        WindowGroup {
            TabRootView()
                .environmentObject(connectionManager)
                .environmentObject(pushService)
            .onAppear {
                #if os(iOS)
                appDelegate.pushService = pushService
                UNUserNotificationCenter.current().delegate = appDelegate
                #endif
            }
            .onChange(of: connectionManager.isConnected) { _, isConnected in
                if isConnected {
                    pushService.configure(
                        serverURL: connectionManager.serverURL,
                        apiToken: connectionManager.apiToken
                    )
                    pushService.requestPermission()
                }
            }
        }
    }
}
