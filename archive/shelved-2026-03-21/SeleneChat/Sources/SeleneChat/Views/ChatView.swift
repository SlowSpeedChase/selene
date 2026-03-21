import SeleneShared
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @EnvironmentObject var databaseService: DatabaseService
    @EnvironmentObject var speechService: SpeechRecognitionService
    @EnvironmentObject var speechSynthesisService: SpeechSynthesisService
    @State private var messageText = ""
    @State private var showingSessionHistory = false
    @State private var isAPIAvailable = false
    @State private var wasVoiceInput = false
    @FocusState private var isInputFocused: Bool
    @Namespace private var focusNamespace

    var initialQuery: String?
    var briefingCard: BriefingCard?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(chatViewModel.currentSession.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }

                        // Show thinking indicator when processing
                        if chatViewModel.isProcessing {
                            HStack {
                                ThinkingIndicator()
                                    .transition(.scale.combined(with: .opacity))
                                Spacer()
                            }
                            .id("thinking-indicator")
                        }
                    }
                    .padding()
                }
                .onChange(of: chatViewModel.currentSession.messages.count) {
                    if let lastMessage = chatViewModel.currentSession.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chatViewModel.isProcessing) {
                    // Scroll to thinking indicator when it appears
                    if chatViewModel.isProcessing {
                        withAnimation {
                            proxy.scrollTo("thinking-indicator", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            chatInput
        }
        .focusScope(focusNamespace)
        .sheet(isPresented: $showingSessionHistory) {
            SessionHistoryView()
                .environmentObject(chatViewModel)
        }
        .onAppear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Appeared: ChatView")
            ActionTracker.shared.track(action: "viewAppeared", params: ["view": "ChatView"])
            #endif

            // Check API availability for vector search
            Task {
                isAPIAvailable = await databaseService.isAPIAvailable()
            }

            // Handle initial query from Today view thread tap
            if let query = initialQuery, !query.isEmpty {
                messageText = query
                // Auto-send the query
                Task {
                    await chatViewModel.sendMessage(query)
                }
                // Note: We don't clear messageText here since sendMessage handles that logic
            }

            // Handle briefing card discussion (from morning briefing)
            if let card = briefingCard {
                Task {
                    await chatViewModel.startBriefingDiscussion(card: card)
                }
            }
        }
        .onDisappear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Disappeared: ChatView")
            #endif
        }
    }

    private var chatHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chatViewModel.currentSession.title)
                    .font(.headline)

                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: databaseService.isConnected ? "circle.fill" : "circle")
                            .foregroundColor(databaseService.isConnected ? .green : .red)
                            .font(.caption)

                        Text(databaseService.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 4) {
                        Circle()
                            .fill(isAPIAvailable ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(isAPIAvailable ? "Semantic" : "Keywords")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .help(isAPIAvailable ? "Vector search available" : "Using keyword search (server offline)")
                }
            }

            Spacer()

            Button(action: { showingSessionHistory = true }) {
                Label("History", systemImage: "clock.arrow.circlepath")
            }

            Button(action: { chatViewModel.newSession() }) {
                Label("New Chat", systemImage: "plus.message")
            }
        }
        .padding()
    }

    private var chatInput: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask about your notes...", text: speechService.state == .listening ? $speechService.liveText : $messageText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .prefersDefaultFocus(in: focusNamespace)
                .lineLimit(1...5)
                .disabled(chatViewModel.isProcessing)
                .onSubmit {
                    sendMessage()
                }
                .onChange(of: speechService.state) { _, newState in
                    if newState == .listening {
                        // Stop any in-progress TTS when user starts speaking
                        speechSynthesisService.stop()
                    }
                    // When listening stops, transfer liveText to messageText for editing
                    if newState == .idle && !speechService.liveText.isEmpty {
                        messageText = speechService.liveText
                        speechService.liveText = ""
                        isInputFocused = true
                        wasVoiceInput = true
                    }
                }
                .onKeyPress(.escape) {
                    if speechService.state == .listening {
                        speechService.cancel()
                        messageText = ""
                        return .handled
                    }
                    return .ignored
                }

            VoiceMicButton(
                speechService: speechService,
                isDisabled: chatViewModel.isProcessing
            )

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(messageText.isEmpty ? .gray : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(messageText.isEmpty || chatViewModel.isProcessing)
        }
        .padding()
    }

    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let message = messageText
        let voiceOriginated = wasVoiceInput
        messageText = ""
        wasVoiceInput = false

        Task {
            await chatViewModel.sendMessage(message, voiceOriginated: voiceOriginated)
        }
    }
}

struct MessageBubble: View {
    let message: Message
    @State private var selectedNote: Note?
    @EnvironmentObject var databaseService: DatabaseService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                assistantIcon
            } else {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content)
                .padding(12)
                .background(backgroundColor)
                .foregroundColor(textColor)
                .cornerRadius(12)
                .textSelection(.enabled)

                // Clickable context notes
                if let contextNotes = message.contextNotes, !contextNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Referenced Notes")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        ForEach(contextNotes) { note in
                            Button {
                                selectedNote = note
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text")
                                        .font(.caption)
                                    Text(note.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .foregroundColor(.accentColor)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                // Metadata
                HStack(spacing: 8) {
                    if message.role == .assistant {
                        tierBadge
                    }

                    Text(message.formattedTime)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if let noteIds = message.relatedNotes, !noteIds.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                            Text("\(noteIds.count)")
                                .font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }

            if message.role == .user {
                userIcon
            } else {
                Spacer()
            }
        }
        .sheet(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor
        case .assistant:
            return Color(NSColor.controlBackgroundColor)
        case .system:
            return Color.yellow.opacity(0.2)
        }
    }

    private var textColor: Color {
        message.role == .user ? .white : .primary
    }

    private var assistantIcon: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 32, height: 32)

            Image(systemName: "brain.head.profile")
                .foregroundColor(.accentColor)
                .font(.system(size: 14))
        }
    }

    private var userIcon: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 32, height: 32)

            Image(systemName: "person.fill")
                .foregroundColor(.gray)
                .font(.system(size: 14))
        }
    }

    private var tierBadge: some View {
        HStack(spacing: 2) {
            Text(message.llmTier.icon)
                .font(.caption2)
            Text(message.llmTier.rawValue)
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tierColor.opacity(0.2))
        .cornerRadius(4)
    }

    private var tierColor: Color {
        switch message.llmTier {
        case .onDevice: return .green
        case .privateCloud: return .blue
        case .external: return .orange
        case .local: return .purple
        }
    }
}

struct SessionHistoryView: View {
    @EnvironmentObject var chatViewModel: ChatViewModel
    @Environment(\.dismiss) var dismiss

    var sortedSessions: [ChatSession] {
        chatViewModel.sessions.sorted { session1, session2 in
            // Pinned sessions first
            if session1.isPinned != session2.isPinned {
                return session1.isPinned
            }
            // Then by most recent update
            return session1.updatedAt > session2.updatedAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedSessions) { session in
                    SessionRow(session: session)
                        .onTapGesture {
                            chatViewModel.loadSession(session)
                            dismiss()
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                chatViewModel.togglePin(session)
                            } label: {
                                Label(session.isPinned ? "Unpin" : "Pin",
                                      systemImage: session.isPinned ? "pin.slash" : "pin")
                            }
                            .tint(session.isPinned ? .orange : .blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                chatViewModel.deleteSession(session)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle("Chat History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 450, height: 550)
    }
}

struct SessionRow: View {
    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title with pin indicator
            HStack(spacing: 6) {
                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Text(session.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                compressionBadge
            }

            // Metadata row
            HStack {
                Text(session.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(session.messages.count) messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Summary text for compressed sessions
            if session.compressionState == .compressed, let summary = session.summaryText {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var compressionBadge: some View {
        switch session.compressionState {
        case .full:
            Text("Full")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(4)

        case .processing:
            Text("Processing")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.2))
                .foregroundColor(.orange)
                .cornerRadius(4)

        case .compressed:
            Text("Summary")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)
        }
    }
}
