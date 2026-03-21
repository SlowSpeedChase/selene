import SeleneShared
import SwiftUI

struct ContentView: View {
    @State private var selectedView: NavigationItem = .today
    @State private var pendingThreadQuery: String?
    @State private var pendingBriefingCard: BriefingCard?
    @State private var showBriefing = true  // Show briefing on app open
    @State private var selectedThreadId: Int64?  // For thread workspace navigation
    @EnvironmentObject var databaseService: DatabaseService

    enum NavigationItem: String, CaseIterable {
        case today = "Today"
        case threads = "Threads"
        case chat = "Chat"
        case search = "Search"
        case planning = "Planning"

        var icon: String {
            switch self {
            case .today: return "sun.horizon.fill"
            case .threads: return "flame.fill"
            case .chat: return "message.fill"
            case .search: return "magnifyingglass"
            case .planning: return "list.bullet.clipboard"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(NavigationItem.allCases, id: \.self, selection: $selectedView) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("Selene")
            .frame(minWidth: 200)
        } detail: {
            if let threadId = selectedThreadId {
                // Thread Workspace view
                ThreadWorkspaceView(threadId: threadId, onDismiss: { selectedThreadId = nil })
                    .environmentObject(databaseService)
            } else if showBriefing {
                BriefingView(
                    onDismiss: {
                        showBriefing = false
                    },
                    onDiscussCard: { card in
                        showBriefing = false
                        pendingBriefingCard = card
                        selectedView = .chat
                    }
                )
                .environmentObject(databaseService)
            } else {
                switch selectedView {
                case .today:
                    TodayView(
                        onThreadSelected: { thread in
                            selectedThreadId = thread.id
                        },
                        onNoteThreadTap: { note in
                            if let threadId = note.threadId {
                                selectedThreadId = threadId
                            }
                        }
                    )
                case .threads:
                    ThreadListSidebarView(
                        onThreadSelected: { threadId in
                            selectedThreadId = threadId
                        }
                    )
                    .environmentObject(databaseService)
                case .chat:
                    ChatView(initialQuery: pendingThreadQuery, briefingCard: pendingBriefingCard)
                        .onAppear {
                            pendingThreadQuery = nil
                            pendingBriefingCard = nil
                        }
                case .search:
                    SearchView()
                case .planning:
                    PlanningView()
                }
            }
        }
        .onAppear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Appeared: ContentView")
            ActionTracker.shared.track(action: "viewAppeared", params: ["view": "ContentView"])
            #endif
        }
        .onDisappear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Disappeared: ContentView")
            #endif
        }
    }
}
