import SeleneShared
import SwiftUI
import AppKit
import ServiceManagement

@main
struct SeleneChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var databaseService = DatabaseService.shared
    @StateObject private var chatViewModel = ChatViewModel(
        dataProvider: DatabaseService.shared,
        llmProvider: OllamaService.shared
    )
    @StateObject private var compressionService = CompressionService(databaseService: DatabaseService.shared)
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var scheduler = WorkflowScheduler()
    @StateObject private var speechSynthesisService = SpeechSynthesisService()
    @StateObject private var chunkingPipeline = BackgroundChunkingPipeline()

    init() {
        // Start as menu bar accessory — no dock icon until window opens
        NSApplication.shared.setActivationPolicy(.accessory)

        // Configure services with database connection
        configureServices()

        // Register as login item (user can manage in System Settings > General > Login Items)
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }

        #if DEBUG
        setupDebugSystem()
        #endif
    }

    private func configureServices() {
        // Configure InboxService and ProjectService with database connection
        // These services need the db connection to query inbox notes and projects
        if let db = DatabaseService.shared.db {
            InboxService.shared.configure(with: db)
            ProjectService.shared.configure(with: db)
        }

        // Configure ThingsURLService with DatabaseService for task_links recording
        ThingsURLService.shared.configure(with: DatabaseService.shared)
    }

    #if DEBUG
    private func setupDebugSystem() {
        DebugLogger.shared.log(.state, "App launched")

        // Register snapshot providers
        DebugSnapshotService.shared.registerProvider(named: "actions", provider: ActionTracker.shared)

        // Note: chatViewModel registration moved to .task modifier in body
        // because ChatViewModel is @MainActor isolated

        // Start watching for snapshot requests
        DebugSnapshotService.shared.startWatching()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseService)
                .environmentObject(chatViewModel)
                .environmentObject(speechService)
                .environmentObject(scheduler)
                .environmentObject(speechSynthesisService)
                .frame(minWidth: 800, minHeight: 600)
                .task {
                    // Show dock icon when window opens
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)

                    // Install Silver Crystal menu bar icon (once)
                    if appDelegate.crystalStatusItem == nil {
                        let crystal = CrystalStatusItem(scheduler: scheduler)
                        crystal.install()
                        appDelegate.crystalStatusItem = crystal
                    }

                    // Start scheduler on first window open
                    if !scheduler.isEnabled {
                        scheduler.enable()
                    }

                    chatViewModel.speechSynthesisService = speechSynthesisService

                    // Run compression check asynchronously on launch
                    await compressionService.checkAndCompressSessions()

                    // Backfill memory embeddings in background
                    Task.detached(priority: .background) {
                        do {
                            let count = try await MemoryService.shared.backfillEmbeddings()
                            if count > 0 {
                                #if DEBUG
                                DebugLogger.shared.log(.state, "SeleneChatApp: backfilled \(count) memory embeddings")
                                #endif
                            }
                        } catch {
                            #if DEBUG
                            DebugLogger.shared.log(.error, "SeleneChatApp: memory backfill failed - \(error)")
                            #endif
                        }
                    }

                    // Start background chunking pipeline
                    chunkingPipeline.start()

                    #if DEBUG
                    // Register chatViewModel provider on main actor
                    await MainActor.run {
                        DebugSnapshotService.shared.registerProvider(named: "chatViewModel", provider: chatViewModel)
                    }
                    #endif
                }
                .onOpenURL { url in
                    let action = VoiceInputManager.parseURL(url)
                    if action == .activateVoice {
                        speechSynthesisService.stop()
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        Task {
                            try? await Task.sleep(for: .milliseconds(200))
                            await speechService.startListening()
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(databaseService)
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    /// The Silver Crystal menu bar icon manager.
    var crystalStatusItem: CrystalStatusItem?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when windows close — stay in menu bar
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        return false
    }
}
