import SeleneShared
import Foundation

@MainActor
class BriefingViewModel: ObservableObject {
    @Published var state = BriefingState()
    @Published var isDismissed = false

    private let databaseService = DatabaseService.shared
    private let ollamaService = OllamaService.shared
    private let contextBuilder = BriefingContextBuilder()

    private static let lastOpenKey = "briefing_last_open_date"

    // MARK: - Load Briefing

    func loadBriefing() async {
        state.status = .loading

        do {
            // Track 1: What Changed (pure DB)
            let lastOpen = UserDefaults.standard.object(forKey: Self.lastOpenKey) as? Date
                ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())!

            let recentNotes = try await databaseService.getNotesSince(lastOpen, limit: 20)
            let noteIds = recentNotes.map { $0.id }
            let threadMap = noteIds.isEmpty ? [:] : try await databaseService.getThreadAssignmentsForNotes(noteIds)
            let whatChangedCards = buildWhatChangedCards(notes: recentNotes, threadMap: threadMap)

            // Track 2: Needs Attention (pure DB)
            let activeThreads = try await databaseService.getActiveThreads(limit: 20)
            let stalledThreads = BriefingDataService.identifyStalledThreads(activeThreads, staleDays: 5)

            var openTaskCounts: [Int64: Int] = [:]
            for thread in stalledThreads {
                let tasks = try await databaseService.getTasksForThread(thread.id)
                openTaskCounts[thread.id] = tasks.filter { !$0.isCompleted }.count
            }
            let needsAttentionCards = buildNeedsAttentionCards(threads: stalledThreads, openTaskCounts: openTaskCounts)

            // Track 3: Connections (embeddings + LLM)
            var connectionCards: [BriefingCard] = []
            do {
                let pairs = try await databaseService.getCrossThreadAssociations(minSimilarity: 0.7, recentDays: 7, limit: 3)
                if !pairs.isEmpty {
                    connectionCards = await buildConnectionCardsFromPairs(pairs)
                }
            } catch {
                // Connections are optional — continue without them
            }

            // Track 4: LLM Intro (or fallback)
            let intro = await generateIntro(
                whatChanged: whatChangedCards,
                needsAttention: needsAttentionCards,
                connections: connectionCards
            )

            let briefing = StructuredBriefing(
                intro: intro,
                whatChanged: whatChangedCards,
                needsAttention: needsAttentionCards,
                connections: connectionCards,
                generatedAt: Date()
            )

            state.status = .loaded(briefing)
            UserDefaults.standard.set(Date(), forKey: Self.lastOpenKey)

        } catch {
            state.status = .failed(error.localizedDescription)
        }
    }

    func dismiss() async {
        isDismissed = true
    }

    // MARK: - Card Builders (internal for testing)

    func buildWhatChangedCards(notes: [Note], threadMap: [Int: (threadName: String, threadId: Int64)]) -> [BriefingCard] {
        notes.map { note in
            let assignment = threadMap[note.id]
            return BriefingCard.whatChanged(
                noteTitle: note.title,
                noteId: note.id,
                threadName: assignment?.threadName,
                threadId: assignment?.threadId,
                date: note.createdAt,
                primaryTheme: note.primaryTheme,
                energyLevel: note.energyLevel
            )
        }
    }

    func buildNeedsAttentionCards(threads: [Thread], openTaskCounts: [Int64: Int]) -> [BriefingCard] {
        threads.map { thread in
            let taskCount = openTaskCounts[thread.id] ?? 0
            let daysSince = daysSinceLastActivity(thread)

            var reasons: [String] = []
            if daysSince >= 5 {
                reasons.append("no activity in \(daysSince) days")
            }
            if taskCount > 0 {
                reasons.append("\(taskCount) open task\(taskCount == 1 ? "" : "s")")
            }
            if reasons.isEmpty {
                reasons.append("needs review")
            }

            return BriefingCard.needsAttention(
                threadName: thread.name,
                threadId: thread.id,
                reason: reasons.joined(separator: ", "),
                noteCount: thread.noteCount,
                openTaskCount: taskCount
            )
        }
    }

    func buildConnectionCards(connections: [(noteA: Note, noteB: Note, threadAName: String, threadBName: String, explanation: String)]) -> [BriefingCard] {
        connections.map { conn in
            BriefingCard.connection(
                noteATitle: conn.noteA.title,
                noteAId: conn.noteA.id,
                threadAName: conn.threadAName,
                noteBTitle: conn.noteB.title,
                noteBId: conn.noteB.id,
                threadBName: conn.threadBName,
                explanation: conn.explanation
            )
        }
    }

    func buildFallbackIntro(changedCount: Int, attentionCount: Int, connectionCount: Int) -> String {
        if changedCount == 0 && attentionCount == 0 && connectionCount == 0 {
            return "Nothing new since last time."
        }

        var parts: [String] = []

        if changedCount > 0 {
            parts.append("\(changedCount) new note\(changedCount == 1 ? "" : "s")")
        }
        if attentionCount > 0 {
            parts.append("\(attentionCount) thread\(attentionCount == 1 ? "" : "s") need\(attentionCount == 1 ? "s" : "") attention")
        }
        if connectionCount > 0 {
            parts.append("\(connectionCount) connection\(connectionCount == 1 ? "" : "s") found")
        }

        return parts.joined(separator: ", ") + "."
    }

    // MARK: - Helpers

    func daysSinceLastActivity(_ thread: Thread) -> Int {
        guard let lastActivity = thread.lastActivityAt else { return 999 }
        return Calendar.current.dateComponents([.day], from: lastActivity, to: Date()).day ?? 0
    }

    private func buildConnectionCardsFromPairs(_ pairs: [(noteAId: Int, noteBId: Int, similarity: Double)]) async -> [BriefingCard] {
        var cards: [BriefingCard] = []

        for pair in pairs.prefix(3) {
            do {
                guard let noteA = try await databaseService.getNote(byId: pair.noteAId),
                      let noteB = try await databaseService.getNote(byId: pair.noteBId) else { continue }

                let threadMapA = try await databaseService.getThreadAssignmentsForNotes([pair.noteAId])
                let threadMapB = try await databaseService.getThreadAssignmentsForNotes([pair.noteBId])

                let threadAName = threadMapA[pair.noteAId]?.threadName ?? "Unthreaded"
                let threadBName = threadMapB[pair.noteBId]?.threadName ?? "Unthreaded"

                let explanation = await generateConnectionExplanation(noteA: noteA, noteB: noteB)

                cards.append(BriefingCard.connection(
                    noteATitle: noteA.title,
                    noteAId: noteA.id,
                    threadAName: threadAName,
                    noteBTitle: noteB.title,
                    noteBId: noteB.id,
                    threadBName: threadBName,
                    explanation: explanation
                ))
            } catch {
                continue
            }
        }

        return cards
    }

    private func generateConnectionExplanation(noteA: Note, noteB: Note) async -> String {
        let isAvailable = await ollamaService.isAvailable()
        guard isAvailable else {
            return fallbackConnectionExplanation(noteA: noteA, noteB: noteB)
        }

        let prompt = """
        You are analyzing two notes from different thinking threads. Explain in ONE sentence \
        what connects them conceptually. Be specific, not generic.

        Note A: "\(noteA.title)"
        \(String(noteA.content.prefix(300)))

        Note B: "\(noteB.title)"
        \(String(noteB.content.prefix(300)))

        Connection (one sentence):
        """

        do {
            let response = try await ollamaService.generate(prompt: prompt, model: "mistral:7b")
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstSentence = trimmed.components(separatedBy: ".").first, !firstSentence.isEmpty {
                return firstSentence.trimmingCharacters(in: .whitespaces) + "."
            }
            return trimmed
        } catch {
            return fallbackConnectionExplanation(noteA: noteA, noteB: noteB)
        }
    }

    private func fallbackConnectionExplanation(noteA: Note, noteB: Note) -> String {
        let conceptsA = Set(noteA.concepts ?? [])
        let conceptsB = Set(noteB.concepts ?? [])
        let shared = conceptsA.intersection(conceptsB)

        if !shared.isEmpty {
            return "Shared concepts: \(shared.sorted().joined(separator: ", "))"
        }

        return "High semantic similarity"
    }

    private func generateIntro(
        whatChanged: [BriefingCard],
        needsAttention: [BriefingCard],
        connections: [BriefingCard]
    ) async -> String {
        let isAvailable = await ollamaService.isAvailable()
        guard isAvailable else {
            return buildFallbackIntro(changedCount: whatChanged.count, attentionCount: needsAttention.count, connectionCount: connections.count)
        }

        // Build specific context so the LLM can reference real content
        var context = ""

        if !whatChanged.isEmpty {
            let titles = whatChanged.prefix(5).compactMap { $0.noteTitle }
            let threads = Set(whatChanged.compactMap { $0.threadName })
            context += "New notes: \(titles.joined(separator: ", "))\n"
            if !threads.isEmpty {
                context += "In threads: \(threads.joined(separator: ", "))\n"
            }
        }

        if !needsAttention.isEmpty {
            let threadNames = needsAttention.compactMap { $0.threadName }
            context += "Stalled threads: \(threadNames.joined(separator: ", "))\n"
        }

        if !connections.isEmpty {
            let pairs = connections.prefix(2).map { card in
                "\(card.noteATitle ?? "?") <-> \(card.noteBTitle ?? "?")"
            }
            context += "Connections found: \(pairs.joined(separator: "; "))\n"
        }

        let prompt = """
        You are Selene, a thinking partner for someone with ADHD. Write a 1-2 sentence morning \
        briefing intro that references SPECIFIC topics from the data below. Don't be generic — \
        name actual threads or note topics. Be warm but direct.

        \(context)

        Keep it under 40 words. No bullet points. Reference at least one specific topic by name.
        """

        do {
            let response = try await ollamaService.generate(prompt: prompt, model: "mistral:7b")
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return buildFallbackIntro(changedCount: whatChanged.count, attentionCount: needsAttention.count, connectionCount: connections.count)
        }
    }
}
