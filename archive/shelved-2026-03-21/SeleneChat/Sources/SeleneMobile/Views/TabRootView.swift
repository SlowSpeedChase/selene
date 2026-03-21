import SwiftUI
import SeleneShared

struct TabRootView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        TabView {
            if let dp = connectionManager.dataProvider, let llm = connectionManager.llmProvider {
                MobileChatView(dataProvider: dp, llmProvider: llm)
                    .tabItem { Label("Chat", systemImage: "message") }

                MobileThreadsView(dataProvider: dp, llmProvider: llm)
                    .tabItem { Label("Threads", systemImage: "circle.hexagongrid") }

                MobileBriefingView(dataProvider: dp)
                    .tabItem { Label("Briefing", systemImage: "sun.max") }
            } else {
                ProgressView("Connecting...")
                    .tabItem { Label("Chat", systemImage: "message") }
            }

            MobileSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
