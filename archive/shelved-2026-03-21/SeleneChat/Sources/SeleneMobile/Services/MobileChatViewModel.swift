import Foundation
import SeleneShared
#if os(iOS)
import ActivityKit
#endif

@MainActor
class MobileChatViewModel: ObservableObject {
    @Published var currentSession: ChatSession
    @Published var sessions: [ChatSession] = []
    @Published var isProcessing = false
    @Published var error: String?
    @Published var useConversationHistory = true
    @Published var activeDeepDiveThread: SeleneShared.Thread?

    private let dataProvider: DataProvider
    private let llmProvider: LLMProvider
    private let queryAnalyzer = QueryAnalyzer()
    private let contextBuilder = ContextBuilder()
    private let deepDivePromptBuilder = DeepDivePromptBuilder()
    private let synthesisPromptBuilder = SynthesisPromptBuilder()
    private let actionExtractor = ActionExtractor()
    private let privacyRouter = PrivacyRouter.shared

    #if os(iOS)
    private let liveActivityManager = LiveActivityManager()
    #endif

    init(dataProvider: DataProvider, llmProvider: LLMProvider) {
        self.dataProvider = dataProvider
        self.llmProvider = llmProvider
        self.currentSession = ChatSession()
        Task {
            await loadSessions()
        }
    }

    // MARK: - Send Message

    func sendMessage(_ content: String) async {
        isProcessing = true
        #if os(iOS)
        await liveActivityManager.startActivity(query: content)
        #endif
        defer { isProcessing = false }

        let userMessage = Message(
            role: .user,
            content: content,
            llmTier: .local
        )
        currentSession.addMessage(userMessage)

        do {
            // Check for thread queries first
            if let threadIntent = queryAnalyzer.detectThreadIntent(content) {
                #if os(iOS)
                await liveActivityManager.updateActivity(status: "Loading threads...", progress: 0.5)
                #endif
                let response = try await handleThreadQuery(intent: threadIntent)
                let assistantMessage = Message(role: .assistant, content: response, llmTier: .onDevice, queryType: "thread")
                currentSession.addMessage(assistantMessage)
                await saveSession()
                #if os(iOS)
                await liveActivityManager.endActivity()
                #endif
                return
            }

            // Check for synthesis queries
            if queryAnalyzer.detectSynthesisIntent(content) {
                #if os(iOS)
                await liveActivityManager.updateActivity(status: "Synthesizing threads...", progress: 0.4)
                #endif
                let (response, citedNotes, contextNotes, queryType) = try await handleSynthesisQuery(query: content)
                let assistantMessage = Message(role: .assistant, content: response, llmTier: .local,
                                              citedNotes: citedNotes, contextNotes: contextNotes, queryType: queryType)
                currentSession.addMessage(assistantMessage)
                await saveSession()
                #if os(iOS)
                await liveActivityManager.endActivity()
                #endif
                return
            }

            // Check for deep-dive queries
            if let deepDiveIntent = queryAnalyzer.detectDeepDiveIntent(content) {
                #if os(iOS)
                await liveActivityManager.updateActivity(status: "Deep-diving...", progress: 0.4)
                #endif
                let (response, citedNotes, contextNotes, queryType) = try await handleDeepDiveQuery(
                    threadName: deepDiveIntent.threadName, query: content)
                let assistantMessage = Message(role: .assistant, content: response, llmTier: .local,
                                              citedNotes: citedNotes, contextNotes: contextNotes, queryType: queryType)
                currentSession.addMessage(assistantMessage)
                await saveSession()
                #if os(iOS)
                await liveActivityManager.endActivity()
                #endif
                return
            }

            // Standard query with LLM
            #if os(iOS)
            await liveActivityManager.updateActivity(status: "Thinking...", progress: 0.6)
            #endif
            let (response, citedNotes, contextNotes, queryType) = try await handleOllamaQuery(query: content)
            let assistantMessage = Message(role: .assistant, content: response, llmTier: .local,
                                          citedNotes: citedNotes, contextNotes: contextNotes, queryType: queryType)
            currentSession.addMessage(assistantMessage)
            await saveSession()

            // Save conversation messages (no memory extraction on iOS)
            saveConversationMessages(userMessage: content, assistantResponse: response)

            #if os(iOS)
            await liveActivityManager.endActivity()
            #endif

        } catch {
            self.error = error.localizedDescription
            let errorMessage = Message(role: .assistant,
                                      content: "I encountered an error: \(error.localizedDescription)",
                                      llmTier: .onDevice)
            currentSession.addMessage(errorMessage)
            #if os(iOS)
            await liveActivityManager.endActivity()
            #endif
        }
    }

    // MARK: - LLM Query

    private func handleOllamaQuery(query: String) async throws -> (response: String, citedNotes: [Note], contextNotes: [Note], queryType: String) {
        let isAvailable = await llmProvider.isAvailable()
        guard isAvailable else {
            return ("Selene's LLM is not available. Make sure Ollama is running on your Mac.", [], [], "unavailable")
        }

        let analysis = queryAnalyzer.analyze(query)
        let useSemantic = queryAnalyzer.shouldUseSemanticSearch(query)
        let limit = limitFor(queryType: analysis.queryType)

        let notes: [Note]
        if useSemantic {
            notes = await dataProvider.searchNotesSemantically(query: query, limit: limit)
        } else {
            notes = try await dataProvider.retrieveNotesFor(
                queryType: analysis.queryType, keywords: analysis.keywords,
                timeScope: analysis.timeScope, limit: limit)
        }

        guard !notes.isEmpty else {
            return ("I don't have any notes matching that query yet. Try asking about something else or capture more notes first.", [], [], String(describing: analysis.queryType))
        }

        let noteContext = contextBuilder.buildContext(notes: notes, queryType: analysis.queryType)
        let systemPrompt = buildSystemPrompt(for: analysis.queryType)

        let historySection: String
        if useConversationHistory {
            let priorMessages = Array(currentSession.messages.dropLast())
            let sessionContext = SessionContext(messages: priorMessages)
            historySection = priorMessages.isEmpty ? "" : "\n## Conversation so far:\n\(sessionContext.historyWithSummary())\n"
        } else {
            historySection = ""
        }

        let fullPrompt = """
        \(systemPrompt)
        \(historySection)
        Notes:
        \(noteContext)

        Question: \(query)
        """

        do {
            let response = try await llmProvider.generate(prompt: fullPrompt, model: "mistral:7b")
            return (response, notes, notes, String(describing: analysis.queryType))
        } catch {
            return ("I had trouble generating a response. Please try again.", notes, notes, "error-fallback")
        }
    }

    // MARK: - Thread Queries

    private func handleThreadQuery(intent: QueryAnalyzer.ThreadQueryIntent) async throws -> String {
        switch intent {
        case .listActive:
            return try await formatActiveThreads()
        case .showSpecific(let name):
            return try await formatThreadDetails(name: name)
        }
    }

    private func formatActiveThreads() async throws -> String {
        let threads = try await dataProvider.getActiveThreads(limit: 10)
        guard !threads.isEmpty else {
            return "No active threads yet.\n\nThreads emerge when 3+ related notes cluster together. Keep capturing notes!"
        }

        var response = "**Active Threads** (by momentum)\n\n"
        for (index, thread) in threads.enumerated() {
            response += "\(index + 1). **\(thread.name)** (momentum: \(thread.momentumDisplay))\n"
            response += "   -> \(thread.noteCount) notes | Last activity: \(thread.lastActivityDisplay)\n"
            let summary = thread.summary ?? "No summary yet"
            response += "   \"\(summary.prefix(100))\(summary.count > 100 ? "..." : "")\"\n\n"
        }
        response += "_Ask \"show me [thread name] thread\" for details._"
        return response
    }

    private func formatThreadDetails(name: String) async throws -> String {
        guard let (thread, notes) = try await dataProvider.getThreadByName(name) else {
            return "I couldn't find a thread matching \"\(name)\".\n\nTry \"what's emerging\" to see your active threads."
        }

        var response = "**\(thread.name)**\n\n"
        if let why = thread.why, !why.isEmpty { response += "**Why:** \(why)\n\n" }
        if let summary = thread.summary, !summary.isEmpty { response += "**Summary:** \(summary)\n\n" }
        response += "**Status:** \(thread.status) \(thread.statusEmoji)\n"
        response += "**Momentum:** \(thread.momentumDisplay)\n"
        response += "**Last Activity:** \(thread.lastActivityDisplay)\n\n---\n\n"
        response += "**Linked Notes (\(notes.count)):**\n\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        for (index, note) in notes.prefix(10).enumerated() {
            response += "- [\(index + 1)] \"\(note.title)\" - \(dateFormatter.string(from: note.createdAt))\n"
        }
        if notes.count > 10 { response += "\n_...and \(notes.count - 10) more notes_" }
        return response
    }

    // MARK: - Deep-Dive

    private func handleDeepDiveQuery(threadName: String, query: String) async throws -> (String, [Note], [Note], String) {
        guard let (thread, notes) = try await dataProvider.getThreadByName(threadName) else {
            return ("I couldn't find a thread matching \"\(threadName)\".", [], [], "deep-dive-not-found")
        }
        activeDeepDiveThread = thread

        let prompt: String
        if useConversationHistory {
            let priorMessages = Array(currentSession.messages.dropLast())
            let sessionContext = SessionContext(messages: priorMessages)
            prompt = priorMessages.isEmpty
                ? deepDivePromptBuilder.buildInitialPrompt(thread: thread, notes: notes)
                : deepDivePromptBuilder.buildFollowUpPrompt(thread: thread, notes: notes,
                    conversationHistory: sessionContext.historyWithSummary(), currentQuery: query)
        } else {
            prompt = deepDivePromptBuilder.buildInitialPrompt(thread: thread, notes: notes)
        }

        let response = try await llmProvider.generate(prompt: prompt, model: "mistral:7b")
        let cleanResponse = actionExtractor.removeActionMarkers(from: response)
        return (cleanResponse, notes, notes, "deep-dive")
    }

    // MARK: - Synthesis

    private func handleSynthesisQuery(query: String) async throws -> (String, [Note], [Note], String) {
        let threads = try await dataProvider.getActiveThreads(limit: 10)
        guard !threads.isEmpty else {
            return ("No active threads yet. Keep capturing notes!", [], [], "synthesis-empty")
        }

        var notesPerThread: [Int64: [Note]] = [:]
        for thread in threads {
            if let (_, notes) = try await dataProvider.getThreadByName(thread.name) {
                notesPerThread[thread.id] = Array(notes.prefix(3))
            }
        }

        let prompt: String
        if useConversationHistory {
            let priorMessages = Array(currentSession.messages.dropLast())
            let sessionContext = SessionContext(messages: priorMessages)
            prompt = priorMessages.isEmpty
                ? synthesisPromptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)
                : synthesisPromptBuilder.buildSynthesisPromptWithHistory(threads: threads, notesPerThread: notesPerThread,
                    conversationHistory: sessionContext.historyWithSummary(), currentQuery: query)
        } else {
            prompt = synthesisPromptBuilder.buildSynthesisPrompt(threads: threads, notesPerThread: notesPerThread)
        }

        let response = try await llmProvider.generate(prompt: prompt, model: "mistral:7b")
        let allNotes = notesPerThread.values.flatMap { $0 }
        return (response, allNotes, allNotes, "synthesis")
    }

    // MARK: - Session Management

    func newSession() {
        Task { await saveSession() }
        currentSession = ChatSession()
    }

    func loadSession(_ session: ChatSession) {
        Task { await saveSession() }
        currentSession = session
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        Task { try? await dataProvider.deleteSession(session) }
        if currentSession.id == session.id { newSession() }
    }

    func togglePin(_ session: ChatSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].isPinned.toggle()
            if currentSession.id == session.id {
                currentSession.isPinned = sessions[index].isPinned
            }
            Task {
                try? await dataProvider.updateSessionPin(sessionId: session.id, isPinned: sessions[index].isPinned)
            }
        }
    }

    private func saveSession() async {
        guard !currentSession.messages.isEmpty else { return }
        if let index = sessions.firstIndex(where: { $0.id == currentSession.id }) {
            sessions[index] = currentSession
        } else {
            sessions.append(currentSession)
        }
        try? await dataProvider.saveSession(currentSession)
    }

    private func loadSessions() async {
        sessions = (try? await dataProvider.loadSessions()) ?? []
    }

    private func saveConversationMessages(userMessage: String, assistantResponse: String) {
        Task {
            try? await dataProvider.saveConversationMessage(sessionId: currentSession.id, role: "user", content: userMessage)
            try? await dataProvider.saveConversationMessage(sessionId: currentSession.id, role: "assistant", content: assistantResponse)
        }
    }

    // MARK: - Helpers

    private func limitFor(queryType: QueryAnalyzer.QueryType) -> Int {
        switch queryType {
        case .pattern: return 100
        case .search: return 50
        case .knowledge: return 15
        case .general: return 30
        case .thread: return 50
        case .semantic: return 20
        case .deepDive: return 50
        case .synthesis: return 50
        }
    }

    private func buildSystemPrompt(for queryType: QueryAnalyzer.QueryType) -> String {
        var prompt = """
        You are Selene, a personal AI assistant helping someone with ADHD manage their thoughts and notes.

        Your role:
        - Analyze patterns in their notes (energy, mood, themes, concepts)
        - Provide actionable recommendations
        - Be conversational and supportive
        - Focus on insights that lead to action

        IMPORTANT - Citations:
        - When referencing specific notes, ALWAYS cite them as: [Note: 'Title' - Date]
        - Place citations immediately after the relevant statement
        - Use exact note titles and dates provided in the context

        Guidelines:
        - Keep responses concise but insightful
        - Highlight patterns and correlations when they exist
        - Suggest concrete next steps
        - Be empathetic about ADHD challenges
        """

        switch queryType {
        case .pattern:
            prompt += "\n\nAnalyze these notes for trends and patterns. Look for patterns in energy, themes, sentiment, and timing."
        case .search:
            prompt += "\n\nSummarize what these notes say about the topic. Highlight key points and cite relevant notes."
        case .knowledge:
            prompt += "\n\nAnswer this question based on the note content. Cite specific notes that contain the answer."
        case .general:
            prompt += "\n\nProvide insights based on recent notes. Highlight interesting patterns."
        case .thread:
            prompt += "\n\nShow emerging threads and patterns. Group related ideas and cite specific notes."
        case .semantic:
            prompt += "\n\nExplore the connections and themes in these conceptually related notes."
        case .deepDive:
            prompt += "\n\nAnalyze the thread's evolution, key insights, tensions, and suggest next actions."
        case .synthesis:
            prompt += "\n\nAnalyze active threads and help prioritize where to focus energy."
        }

        return prompt
    }
}
