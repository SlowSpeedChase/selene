import SeleneShared
// SeleneChat/Sources/Views/PlanningView.swift
import SwiftUI

struct PlanningView: View {
    @EnvironmentObject var databaseService: DatabaseService

    @State private var selectedThread: DiscussionThread?
    @State private var selectedProject: Project?

    // Phase 7.2e: Bidirectional Things sync
    @StateObject private var thingsStatusService = ThingsStatusService.shared
    @StateObject private var triggerService = ResurfaceTriggerService.shared
    @State private var isSyncing = false

    // Phase 7.2f: Sub-project suggestions
    @StateObject private var suggestionService = SubprojectSuggestionService.shared
    @State private var isSuggestionsExpanded = true

    // Section collapsed states
    @State private var isActiveProjectsExpanded = true // Start expanded - primary focus
    @State private var isScratchPadExpanded = true     // Start expanded
    @State private var isInboxExpanded = true          // Start expanded - primary triage
    @State private var isParkedProjectsExpanded = false // Start collapsed - less priority

    // Scratch Pad project
    @State private var scratchPad: Project?

    var body: some View {
        Group {
            if let thread = selectedThread {
                PlanningConversationView(
                    thread: thread,
                    onBack: { selectedThread = nil }
                )
            } else if let project = selectedProject {
                ProjectDetailView(
                    project: project,
                    onBack: { selectedProject = nil },
                    onSelectThread: { thread in selectedThread = thread }
                )
            } else {
                mainPlanningView
            }
        }
        .onAppear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Appeared: PlanningView")
            ActionTracker.shared.track(action: "viewAppeared", params: ["view": "PlanningView"])
            #endif
        }
        .onDisappear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Disappeared: PlanningView")
            #endif
        }
    }

    private var mainPlanningView: some View {
        HStack(spacing: 0) {
            // Sidebar for quick navigation
            sectionSidebar

            Divider()

            // Main content
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Planning")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    // Phase 7.2e: Sync indicator
                    if isSyncing {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Syncing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(action: {}) {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                // Scrollable sections
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            // 1. Active projects section - primary focus, limited to 5 for ADHD
                            activeProjectsSection
                                .id("activeProjects")

                            // 2. Scratch Pad section (only if has threads)
                            if let pad = scratchPad, pad.threadCount > 0 {
                                scratchPadSection
                                    .id("scratchPad")
                            }

                            // 3. Sub-project suggestions
                            if !suggestionService.suggestions.isEmpty {
                                suggestionsSection
                                    .id("suggestions")
                            }

                            // 4. Inbox section - notes pending triage
                            inboxSection
                                .id("inbox")

                            // 5. Parked projects section - collapsed by default
                            parkedProjectsSection
                                .id("parkedProjects")
                        }
                        .padding(.bottom)
                    }
                }
            }
        }
        .task {
            // Phase 7.2e: Sync Things statuses when Planning tab opens
            await syncThingsAndEvaluateTriggers()
        }
    }

    // MARK: - Sidebar Navigation

    private var sectionSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sections")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            // 1. Active Projects (always visible)
            sidebarButton(
                icon: "star.fill",
                label: "Active Projects",
                count: nil,
                color: .yellow,
                isExpanded: $isActiveProjectsExpanded
            )

            // 2. Scratch Pad (only if has threads)
            if let pad = scratchPad, pad.threadCount > 0 {
                sidebarButton(
                    icon: "note.text",
                    label: "Scratch Pad",
                    count: pad.threadCount,
                    color: .gray,
                    isExpanded: $isScratchPadExpanded
                )
            }

            // 3. Suggestions (if any)
            if !suggestionService.suggestions.isEmpty {
                sidebarButton(
                    icon: "lightbulb.fill",
                    label: "Suggestions",
                    count: suggestionService.suggestions.count,
                    color: .yellow,
                    isExpanded: $isSuggestionsExpanded
                )
            }

            // 4. Inbox
            sidebarButton(
                icon: "tray",
                label: "Inbox",
                count: nil,
                color: .purple,
                isExpanded: $isInboxExpanded
            )

            // 5. Parked
            sidebarButton(
                icon: "moon.zzz",
                label: "Parked",
                count: nil,
                color: .gray,
                isExpanded: $isParkedProjectsExpanded
            )

            Spacer()
        }
        .frame(width: 140)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func sidebarButton(
        icon: String,
        label: String,
        count: Int?,
        color: Color,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button(action: { withAnimation { isExpanded.wrappedValue.toggle() } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                    .frame(width: 16)

                Text(label)
                    .font(.caption)
                    .lineLimit(1)

                Spacer()

                if let count = count {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Image(systemName: isExpanded.wrappedValue ? "eye" : "eye.slash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isExpanded.wrappedValue ? color.opacity(0.1) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    // MARK: - Collapsible Sections

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (tappable to collapse)
            Button(action: { withAnimation { isInboxExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "tray")
                        .foregroundColor(.purple)
                    Text("Inbox")
                        .font(.headline)

                    Spacer()

                    Image(systemName: isInboxExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isInboxExpanded {
                Divider()
                InboxView()
            }
        }
    }

    private var activeProjectsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (tappable to collapse)
            Button(action: { withAnimation { isActiveProjectsExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Active Projects")
                        .font(.headline)

                    Text("(max 5)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: isActiveProjectsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isActiveProjectsExpanded {
                Divider()
                ActiveProjectsList(onSelectProject: { project in
                    selectedProject = project
                })
            }
        }
    }

    private var parkedProjectsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (tappable to collapse)
            Button(action: { withAnimation { isParkedProjectsExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "moon.zzz")
                        .foregroundColor(.gray)
                    Text("Parked Projects")
                        .font(.headline)

                    Spacer()

                    Image(systemName: isParkedProjectsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isParkedProjectsExpanded {
                Divider()
                ParkedProjectsList(onSelectProject: { project in
                    selectedProject = project
                })
            }
        }
    }

    // MARK: - Scratch Pad Section

    private var scratchPadSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (tappable to collapse)
            Button(action: { withAnimation { isScratchPadExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundColor(.gray)
                    Text("Scratch Pad")
                        .font(.headline)

                    if let pad = scratchPad {
                        Text("(\(pad.threadCount))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isScratchPadExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isScratchPadExpanded, let pad = scratchPad {
                Divider()
                ThreadListView(projectId: pad.id) { thread in
                    selectedThread = thread
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Phase 7.2f: Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Button(action: { withAnimation { isSuggestionsExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Suggestions")
                        .font(.headline)

                    Text("(\(suggestionService.suggestions.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Image(systemName: isSuggestionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isSuggestionsExpanded {
                Divider()

                LazyVStack(spacing: 12) {
                    ForEach(suggestionService.suggestions) { suggestion in
                        SubprojectSuggestionCard(
                            suggestion: suggestion,
                            onApprove: {
                                do {
                                    _ = try await suggestionService.approve(suggestion)
                                    return true
                                } catch {
                                    #if DEBUG
                                    print("[PlanningView] Approve error: \(error)")
                                    #endif
                                    return false
                                }
                            },
                            onDismiss: {
                                Task {
                                    do {
                                        try await suggestionService.dismiss(suggestion)
                                    } catch {
                                        #if DEBUG
                                        print("[PlanningView] Dismiss error: \(error)")
                                        #endif
                                    }
                                }
                            }
                        )
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Phase 7.2e: Bidirectional Things Sync

    /// Sync task statuses from Things and evaluate resurface triggers
    private func syncThingsAndEvaluateTriggers() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            // Load Scratch Pad project
            scratchPad = try await ProjectService.shared.getScratchPad()

            // Only sync with Things if available
            guard thingsStatusService.isAvailable else {
                #if DEBUG
                print("[PlanningView] Things status script not available, skipping sync")
                #endif
                return
            }

            // 1. Get all tracked task IDs
            let taskIds = try await databaseService.getAllTaskLinkIds()
            guard !taskIds.isEmpty else {
                #if DEBUG
                print("[PlanningView] No task links to sync")
                #endif
                return
            }

            #if DEBUG
            print("[PlanningView] Syncing \(taskIds.count) task statuses from Things")
            #endif

            // 2. Sync each task status from Things to database
            let result = await thingsStatusService.syncAllTaskStatuses(taskIds: taskIds) { thingsId, status in
                try await databaseService.updateTaskLinkStatus(
                    thingsId: thingsId,
                    status: status.status,
                    completedAt: status.completionDate
                )
            }

            #if DEBUG
            print("[PlanningView] Sync complete: \(result.synced)/\(result.total) synced, \(result.newlyCompleted) newly completed")
            #endif

            // 3. Evaluate triggers for active planning threads
            let activeThreads = try await databaseService.fetchThreadsByStatus([.active, .pending])

            for thread in activeThreads where thread.threadType == .planning {
                // Get task statuses for this thread
                let threadTaskIds = try await databaseService.fetchTaskIdsForThread(thread.id)
                guard !threadTaskIds.isEmpty else { continue }

                // Build ThingsTaskStatus array from synced data
                var taskStatuses: [ThingsTaskStatus] = []
                for taskId in threadTaskIds {
                    if let status = try? await thingsStatusService.getTaskStatus(thingsId: taskId) {
                        taskStatuses.append(status)
                    }
                }

                guard !taskStatuses.isEmpty else { continue }

                // Evaluate triggers
                if let trigger = triggerService.evaluateTriggers(thread: thread, tasks: taskStatuses) {
                    #if DEBUG
                    print("[PlanningView] Trigger fired for thread \(thread.id): \(trigger.reasonCode)")
                    #endif

                    // Resurface the thread
                    try await databaseService.resurfaceThread(thread.id, reason: trigger.reasonCode)
                }
            }

            // Phase 7.2f: Detect sub-project candidates (service configured in DatabaseService)
            _ = try? await suggestionService.detectCandidates()

        } catch {
            #if DEBUG
            print("[PlanningView] Sync error: \(error)")
            #endif
        }
    }
}

struct PlanningThreadRow: View {
    let thread: DiscussionThread

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with type badge
            HStack {
                Label(thread.threadType.displayName, systemImage: thread.threadType.icon)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(6)

                Spacer()

                // Status indicator
                HStack(spacing: 4) {
                    Image(systemName: thread.status.icon)
                    Text(thread.timeSinceCreated)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            // Prompt
            Text(thread.prompt)
                .font(.body)
                .lineLimit(2)

            // Note title if available
            if let noteTitle = thread.noteTitle {
                Text("From: \(noteTitle)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Resurface reason if applicable
            if let reason = thread.resurfaceReason {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(reason.message)
                }
                .font(.caption)
                .foregroundColor(.orange)
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .contentShape(Rectangle())
    }
}

// Wrapper for pending tasks with stable ID for SwiftUI
struct PendingTask: Identifiable {
    let id = UUID()
    var title: String
    var energy: String
    var minutes: Int

    init(from extracted: ExtractedTask) {
        self.title = extracted.title
        self.energy = extracted.energy
        self.minutes = extracted.minutes
    }
}

struct PlanningConversationView: View {
    let thread: DiscussionThread
    let onBack: () -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @State private var messages: [PlanningMessage] = []
    @State private var inputText = ""
    @State private var isProcessing = false
    @State private var conversationHistory: [[String: String]] = []
    @State private var tasksCreated: [String] = []
    @State private var pendingTasks: [PendingTask] = []  // Queue for approval
    @State private var isSendingTasks = false
    @State private var editingTaskId: UUID? = nil
    @State private var editingTitle = ""
    @FocusState private var isInputFocused: Bool
    @State private var currentProvider: AIProvider = .local
    @State private var showProviderSettings = false
    @State private var showHistoryPrompt = false
    @State private var apiKeyMissing = false
    @StateObject private var providerService = AIProviderService.shared

    private let thingsService = ThingsURLService.shared

    var body: some View {
        HStack(spacing: 0) {
            // Main conversation area
            VStack(spacing: 0) {
                // Header
                conversationHeader

                Divider()

                // Original note context
                noteContextCard

                Divider()

                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { message in
                                PlanningMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if isProcessing {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .id("processing")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) {
                        if let lastMessage = messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // API key error
                if apiKeyMissing {
                    apiKeyErrorView
                }

                // Input
                inputArea
            }

            // Pending tasks sidebar (only show if there are pending or created tasks)
            if !pendingTasks.isEmpty || !tasksCreated.isEmpty {
                Divider()
                pendingTasksSidebar
            }
        }
        .task {
            await startConversation()
        }
    }

    // MARK: - Pending Tasks Sidebar

    private var pendingTasksSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.blue)
                Text("Tasks")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Pending tasks (awaiting approval)
                    if !pendingTasks.isEmpty {
                        Text("Pending Approval")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(pendingTasks) { task in
                            pendingTaskRow(task)
                        }

                        // Send to Things button
                        Button(action: { Task { await sendAllToThings() } }) {
                            HStack {
                                Image(systemName: "paperplane.fill")
                                Text("Send \(pendingTasks.count) to Things")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSendingTasks)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    // Created tasks
                    if !tasksCreated.isEmpty {
                        if !pendingTasks.isEmpty {
                            Divider()
                                .padding(.vertical, 8)
                        }

                        Text("Sent to Things")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)

                        ForEach(tasksCreated, id: \.self) { title in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                Text(title)
                                    .font(.caption)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .frame(width: 240)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    private func pendingTaskRow(_ task: PendingTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if editingTaskId == task.id {
                // Edit mode
                HStack {
                    TextField("Task title", text: $editingTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button(action: { saveEdit(task) }) {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)

                    Button(action: { editingTaskId = nil }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Display mode
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle")
                        .foregroundColor(.orange)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.caption)
                            .lineLimit(2)

                        HStack(spacing: 8) {
                            Label(task.energy, systemImage: "bolt")
                            Label("\(task.minutes)m", systemImage: "clock")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Edit/Remove buttons
                    HStack(spacing: 4) {
                        Button(action: { startEditing(task) }) {
                            Image(systemName: "pencil")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)

                        Button(action: { removeTask(task) }) {
                            Image(systemName: "trash")
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 8)
    }

    private func startEditing(_ task: PendingTask) {
        editingTaskId = task.id
        editingTitle = task.title
    }

    private func saveEdit(_ task: PendingTask) {
        if let index = pendingTasks.firstIndex(where: { $0.id == task.id }) {
            pendingTasks[index].title = editingTitle
        }
        editingTaskId = nil
    }

    private func removeTask(_ task: PendingTask) {
        withAnimation {
            pendingTasks.removeAll { $0.id == task.id }
        }
    }

    private func sendAllToThings() async {
        isSendingTasks = true
        defer { isSendingTasks = false }

        for task in pendingTasks {
            do {
                try await thingsService.createTask(
                    title: task.title,
                    notes: nil,
                    tags: [],
                    energy: task.energy,
                    sourceNoteId: thread.rawNoteId,
                    threadId: thread.id,
                    project: nil,
                    heading: thread.threadName ?? String(thread.prompt.prefix(50))
                )

                await MainActor.run {
                    tasksCreated.append(task.title)

                    // Show confirmation in chat
                    messages.append(PlanningMessage(
                        role: .taskCreated,
                        content: task.title
                    ))
                }

            } catch {
                await MainActor.run {
                    messages.append(PlanningMessage(
                        role: .system,
                        content: "Failed to create '\(task.title)': \(error.localizedDescription)"
                    ))
                }
            }
        }

        await MainActor.run {
            pendingTasks.removeAll()
        }
    }

    private var conversationHeader: some View {
        HStack {
            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain)

            Spacer()

            // Provider toggle badge
            providerBadge

            if !tasksCreated.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(tasksCreated.count) tasks")
                        .font(.caption)
                }
            }

            Spacer()

            // Settings gear
            Button(action: { showProviderSettings = true }) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showProviderSettings) {
                AIProviderSettings(providerService: providerService)
            }

            Button("Complete") {
                Task { await completeThread() }
            }
            .disabled(isProcessing)
        }
        .padding()
        .alert("Switch to Cloud AI", isPresented: $showHistoryPrompt) {
            Button("Yes, send history") {
                currentProvider = .cloud
            }
            Button("No, fresh start") {
                currentProvider = .cloud
                conversationHistory = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Include conversation history? This will send previous messages to Claude API.")
        }
    }

    private var providerBadge: some View {
        Button(action: toggleProvider) {
            HStack(spacing: 4) {
                Text(currentProvider.icon)
                Text(currentProvider.displayName)
                    .font(.caption)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(currentProvider == .cloud ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var apiKeyErrorView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("API key not found")
                    .font(.headline)
                Spacer()
                Button(action: { apiKeyMissing = false; currentProvider = .local }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            Text("Set ANTHROPIC_API_KEY in your shell environment and restart SeleneChat.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("# Add to ~/.zshrc:\nexport ANTHROPIC_API_KEY=\"sk-ant-...\"")
                .font(.system(.caption, design: .monospaced))
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(4)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    private func toggleProvider() {
        if currentProvider == .local {
            // Check if cloud is available before switching
            Task {
                let available = await providerService.isCloudAvailable()
                if available {
                    showHistoryPrompt = true
                } else {
                    apiKeyMissing = true
                }
            }
        } else {
            // Switching to local - no check needed
            currentProvider = .local
        }
    }

    private var noteContextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = thread.noteTitle {
                Text(title)
                    .font(.headline)
            }

            if let content = thread.noteContent {
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.05))
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Your response...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .disabled(isProcessing)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(inputText.isEmpty ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty || isProcessing)
        }
        .padding()
    }

    private func startConversation() async {
        // Set initial provider from global default
        currentProvider = providerService.globalDefault

        // Mark thread as active
        try? await databaseService.updateThreadStatus(thread.id, status: .active)

        let systemPrompt = buildSystemPrompt()

        isProcessing = true

        do {
            let response = try await providerService.sendPlanningMessage(
                userMessage: "Start the planning session.",
                conversationHistory: [],
                systemPrompt: systemPrompt,
                provider: currentProvider
            )

            conversationHistory.append(["role": "user", "content": "Start the planning session."])
            conversationHistory.append(["role": "assistant", "content": response.message])

            messages.append(PlanningMessage(
                role: .assistant,
                content: response.cleanMessage,
                provider: currentProvider
            ))

            await handleExtractedTasks(response.extractedTasks)

        } catch {
            messages.append(PlanningMessage(
                role: .system,
                content: "Failed to start conversation: \(error.localizedDescription)",
                provider: currentProvider
            ))
        }

        isProcessing = false
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let userInput = inputText
        inputText = ""

        // Add user message (no provider tracking for user messages)
        messages.append(PlanningMessage(role: .user, content: userInput))
        conversationHistory.append(["role": "user", "content": userInput])

        isProcessing = true

        Task {
            do {
                let response = try await providerService.sendPlanningMessage(
                    userMessage: userInput,
                    conversationHistory: conversationHistory,
                    systemPrompt: buildSystemPrompt(),
                    provider: currentProvider
                )

                conversationHistory.append(["role": "assistant", "content": response.message])

                messages.append(PlanningMessage(
                    role: .assistant,
                    content: response.cleanMessage,
                    provider: currentProvider
                ))

                await handleExtractedTasks(response.extractedTasks)

            } catch {
                messages.append(PlanningMessage(
                    role: .system,
                    content: "Error: \(error.localizedDescription)",
                    provider: currentProvider
                ))
            }

            isProcessing = false
        }
    }

    private func handleExtractedTasks(_ tasks: [ExtractedTask]) async {
        // Add tasks to pending queue for user approval (don't create immediately)
        for task in tasks {
            await MainActor.run {
                let pending = PendingTask(from: task)
                pendingTasks.append(pending)

                // Show in chat that a task was extracted
                messages.append(PlanningMessage(
                    role: .taskExtracted,
                    content: task.title
                ))
            }
        }
    }

    private func completeThread() async {
        try? await databaseService.updateThreadStatus(thread.id, status: .completed)
        onBack()
    }

    private func buildSystemPrompt() -> String {
        """
        You are a planning assistant helping break down goals into actionable tasks.
        Ask ONE question at a time. When the user's response contains a clear,
        specific action, extract it as a task.

        Context:
        - Original note: \(thread.noteContent ?? "No content")
        - Planning prompt: \(thread.prompt)
        - Tasks already created: \(tasksCreated.joined(separator: ", "))

        Your question types (cycle through as needed):
        1. "What's the first concrete step you could take?"
        2. "What's blocking you from starting?"
        3. "Can you break that down smaller?"
        4. "What would 'done' look like for this?"
        5. "What's the next step after that?"

        When extracting a task, include in your response:
        [TASK: verb + object | energy: low/medium/high | minutes: 5/15/30/60/120/240]

        When planning feels complete, ask: "Does this cover what you need,
        or is there more to plan?"
        """
    }
}

// MARK: - Planning Message Model

struct PlanningMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp = Date()
    let provider: AIProvider  // Track which AI generated this

    enum Role {
        case user
        case assistant
        case system
        case taskCreated
        case taskExtracted  // Task queued for approval
    }

    init(role: Role, content: String, provider: AIProvider = .local) {
        self.role = role
        self.content = content
        self.provider = provider
    }
}

struct PlanningMessageBubble: View {
    let message: PlanningMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                content
                    .padding(12)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(12)

                // Provider indicator for assistant messages
                if message.role == .assistant {
                    HStack(spacing: 4) {
                        Text(message.provider.icon)
                            .font(.caption2)
                        Text(message.provider.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if message.role != .user { Spacer() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.role {
        case .taskCreated:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Sent to Things: \(message.content)")
            }
            .font(.callout)
        case .taskExtracted:
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.orange)
                Text("Task queued: \(message.content)")
            }
            .font(.callout)
        default:
            Text(message.content)
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            // Cloud messages get blue tint
            return message.provider == .cloud
                ? Color.blue.opacity(0.1)
                : Color(NSColor.controlBackgroundColor)
        case .system:
            return Color.orange.opacity(0.2)
        case .taskCreated:
            return Color.green.opacity(0.1)
        case .taskExtracted:
            return Color.orange.opacity(0.1)
        }
    }

    private var textColor: Color {
        message.role == .user ? .white : .primary
    }
}
