import Foundation

/// Builds context for Thinking Partner queries (briefing, synthesis, deep-dive)
public class ThinkingPartnerContextBuilder {

    // MARK: - Init

    public init() {}

    // MARK: - Thread Formatting

    /// Format a single thread for context
    public func formatThread(_ thread: Thread) -> String {
        var result = "**\(thread.name)** (\(thread.status) \(thread.statusEmoji))\n"
        result += "- \(thread.noteCount) notes | Momentum: \(thread.momentumDisplay)\n"
        result += "- Last activity: \(thread.lastActivityDisplay)\n"

        if let why = thread.why, !why.isEmpty {
            result += "- Why: \(why)\n"
        }

        if let summary = thread.summary, !summary.isEmpty {
            let truncatedSummary = String(summary.prefix(150))
            result += "- Summary: \(truncatedSummary)\(summary.count > 150 ? "..." : "")\n"
        }

        return result
    }

    // MARK: - Token Management

    /// Estimate token count (4 chars per token)
    public func estimateTokens(_ text: String) -> Int {
        return text.count / 4
    }

    /// Truncate text to fit within token budget
    public func truncateToFit(_ text: String, maxTokens: Int) -> String {
        let maxChars = maxTokens * 4
        if text.count <= maxChars {
            return text
        }
        return String(text.prefix(maxChars)) + "\n[Truncated for token limit]"
    }

    // MARK: - Briefing Context

    /// Build context for morning briefing
    /// Includes: active threads with momentum, recent notes
    public func buildBriefingContext(threads: [Thread], recentNotes: [Note]) -> String {
        let tokenBudget = ThinkingPartnerQueryType.briefing.tokenBudget
        var context = "## Active Threads\n\n"
        var currentTokens = estimateTokens(context)

        // Add threads (sorted by momentum, highest first)
        let sortedThreads = threads.sorted { ($0.momentumScore ?? 0) > ($1.momentumScore ?? 0) }

        for thread in sortedThreads {
            let threadText = formatThread(thread) + "\n"
            let threadTokens = estimateTokens(threadText)

            if currentTokens + threadTokens > tokenBudget - 200 {  // Reserve 200 for notes
                break
            }

            context += threadText
            currentTokens += threadTokens
        }

        // Add recent notes section
        if !recentNotes.isEmpty {
            context += "\n## Recent Notes\n\n"

            for note in recentNotes.prefix(5) {
                let noteText = "- \"\(note.title)\" (\(formatDate(note.createdAt)))\n"
                let noteTokens = estimateTokens(noteText)

                if currentTokens + noteTokens > tokenBudget {
                    break
                }

                context += noteText
                currentTokens += noteTokens
            }
        }

        return context
    }

    // MARK: - Synthesis Context

    /// Build context for cross-thread synthesis ("what should I focus on?")
    /// Includes: all active threads with summaries and recent note titles
    public func buildSynthesisContext(threads: [Thread], notesPerThread: [Int64: [Note]]) -> String {
        let tokenBudget = ThinkingPartnerQueryType.synthesis.tokenBudget
        let truncationMessage = "[Additional threads omitted for token limit]\n"
        let truncationTokens = estimateTokens(truncationMessage)

        var context = "## Threads for Prioritization\n\n"
        var currentTokens = estimateTokens(context)

        // Sort by momentum (highest first)
        let sortedThreads = threads.sorted { ($0.momentumScore ?? 0) > ($1.momentumScore ?? 0) }

        for thread in sortedThreads {
            var threadSection = formatThread(thread)

            // Add note titles for this thread
            if let notes = notesPerThread[thread.id], !notes.isEmpty {
                threadSection += "  Notes:\n"
                for note in notes.prefix(3) {
                    threadSection += "    - \(note.title)\n"
                }
                if notes.count > 3 {
                    threadSection += "    - ...and \(notes.count - 3) more\n"
                }
            }

            threadSection += "\n"
            let sectionTokens = estimateTokens(threadSection)

            // Reserve space for truncation message if we might need it
            if currentTokens + sectionTokens + truncationTokens > tokenBudget {
                context += truncationMessage
                break
            }

            context += threadSection
            currentTokens += sectionTokens
        }

        return context
    }

    // MARK: - Deep-Dive Context

    /// Build context for thread deep-dive exploration
    /// Includes: full thread details + all notes with content (chronological)
    public func buildDeepDiveContext(thread: Thread, notes: [Note]) -> String {
        let tokenBudget = ThinkingPartnerQueryType.deepDive.tokenBudget
        let truncationMessage = "[Older notes omitted for token limit]\n"
        let truncationTokens = estimateTokens(truncationMessage)

        var context = "## Thread: \(thread.name)\n\n"

        // Thread metadata
        context += "Status: \(thread.status) \(thread.statusEmoji)\n"
        context += "Notes: \(thread.noteCount) | Momentum: \(thread.momentumDisplay)\n"

        if let why = thread.why, !why.isEmpty {
            context += "Why this emerged: \(why)\n"
        }

        if let summary = thread.summary, !summary.isEmpty {
            context += "Summary: \(summary)\n"
        }

        context += "\n## Thread Notes (chronological)\n\n"

        var currentTokens = estimateTokens(context)

        // Sort notes chronologically (oldest first for narrative flow)
        let sortedNotes = notes.sorted { $0.createdAt < $1.createdAt }

        for note in sortedNotes {
            var noteSection = "### \(note.title) (\(formatDate(note.createdAt)))\n"
            noteSection += "\(note.content)\n\n"

            let noteTokens = estimateTokens(noteSection)

            // Reserve space for truncation message if we might need it
            if currentTokens + noteTokens + truncationTokens > tokenBudget {
                context += truncationMessage
                break
            }

            context += noteSection
            currentTokens += noteTokens
        }

        return context
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
