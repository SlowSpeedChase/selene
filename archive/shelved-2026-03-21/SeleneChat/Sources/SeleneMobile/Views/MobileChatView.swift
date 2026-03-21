import SwiftUI
import SeleneShared

struct MobileChatView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @StateObject private var viewModel: MobileChatViewModel

    init(dataProvider: DataProvider, llmProvider: LLMProvider) {
        _viewModel = StateObject(wrappedValue: MobileChatViewModel(
            dataProvider: dataProvider, llmProvider: llmProvider))
    }

    @StateObject private var speechService = MobileSpeechService()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.currentSession.messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isProcessing {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                    Text("Thinking...")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.currentSession.messages.count) {
                        if let last = viewModel.currentSession.messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                Divider()

                // Input
                HStack(spacing: 8) {
                    TextField("Ask Selene...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit { sendMessage() }
                        .padding(10)
                        #if os(iOS)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                        #else
                        .background(Color(.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
                        #endif

                    Button(action: toggleVoice) {
                        Image(systemName: speechService.isListening ? "mic.fill" : "mic")
                            .font(.title3)
                            .foregroundStyle(speechService.isListening ? .red : .secondary)
                    }

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(inputText.isEmpty ? .gray : .accentColor)
                    }
                    .disabled(inputText.isEmpty || viewModel.isProcessing)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onChange(of: speechService.transcribedText) { _, newValue in
                    if !newValue.isEmpty {
                        inputText = newValue
                    }
                }
                .onAppear {
                    speechService.requestAuthorization()
                }
            }
            .navigationTitle("Selene")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isProcessing {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sessionMenu
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    if viewModel.isProcessing {
                        ProgressView()
                    }
                }
                ToolbarItem(placement: .automatic) {
                    sessionMenu
                }
            }
            #endif
        }
    }

    private var sessionMenu: some View {
        Menu {
            Button("New Chat", systemImage: "plus") {
                viewModel.newSession()
            }

            if !viewModel.sessions.isEmpty {
                Menu("Recent Sessions") {
                    ForEach(viewModel.sessions.prefix(5)) { session in
                        Button(session.title) {
                            viewModel.loadSession(session)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private func toggleVoice() {
        if speechService.isListening {
            speechService.stopListening()
        } else {
            speechService.startListening()
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isInputFocused = false
        Task {
            await viewModel.sendMessage(text)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(
                        message.role == .user
                            ? Color.accentColor
                            : bubbleBackground
                    )
                    .foregroundStyle(message.role == .user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private var bubbleBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(.windowBackgroundColor)
        #endif
    }
}
