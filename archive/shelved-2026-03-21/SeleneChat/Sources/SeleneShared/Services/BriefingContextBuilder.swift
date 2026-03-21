import Foundation

/// Assembles deep context for "Discuss this" chat sessions from briefing cards.
/// When a user taps "Discuss this" on a briefing card, this service builds the
/// context string that gets sent to the LLM so Selene can have an informed conversation.
public class BriefingContextBuilder {

    /// Context types matching card types
    public enum ContextType {
        case whatChanged
        case needsAttention
        case connection
    }

    // MARK: - Init

    public init() {}

    // MARK: - What Changed Context

    /// Build context for discussing a specific new note.
    /// Includes: full note content, parent thread, related notes, tasks, memories.
    public func buildWhatChangedContext(
        note: Note,
        thread: Thread?,
        relatedNotes: [Note],
        tasks: [ThreadTask],
        memories: [ConversationMemory]
    ) -> String {
        var context = "## Specific Note\n\n"
        context += "### \(note.title) (\(formatDate(note.createdAt)))\n"
        context += "\(note.content)\n\n"

        if let concepts = note.concepts, !concepts.isEmpty {
            context += "Concepts: \(concepts.joined(separator: ", "))\n"
        }
        if let theme = note.primaryTheme {
            context += "Theme: \(theme)\n"
        }
        if let energy = note.energyLevel {
            context += "Energy: \(energy)\n"
        }

        if let thread = thread {
            context += "\n## Parent Thread: \(thread.name)\n"
            if let summary = thread.summary { context += "Summary: \(summary)\n" }
            if let why = thread.why { context += "Why: \(why)\n" }
            context += "Notes: \(thread.noteCount) | Momentum: \(thread.momentumDisplay)\n"
        }

        if !relatedNotes.isEmpty {
            context += "\n## Related Notes (by semantic similarity)\n\n"
            for related in relatedNotes.prefix(3) {
                context += "### \(related.title) (\(formatDate(related.createdAt)))\n"
                context += "\(String(related.content.prefix(300)))\n\n"
            }
        }

        context += formatTasks(tasks)
        context += formatMemories(memories)

        return context
    }

    // MARK: - Needs Attention Context

    /// Build context for discussing a stalled thread.
    /// Includes: thread details, recent notes, tasks, memories.
    public func buildNeedsAttentionContext(
        thread: Thread,
        recentNotes: [Note],
        tasks: [ThreadTask],
        memories: [ConversationMemory]
    ) -> String {
        var context = "## Thread: \(thread.name)\n\n"
        context += "Status: \(thread.status) \(thread.statusEmoji)\n"
        context += "Notes: \(thread.noteCount) | Momentum: \(thread.momentumDisplay)\n"
        context += "Last activity: \(thread.lastActivityDisplay)\n"

        if let why = thread.why { context += "Why this emerged: \(why)\n" }
        if let summary = thread.summary { context += "Summary: \(summary)\n" }

        if !recentNotes.isEmpty {
            context += "\n## Recent Notes in This Thread\n\n"
            for note in recentNotes.prefix(3) {
                context += "### \(note.title) (\(formatDate(note.createdAt)))\n"
                context += "\(String(note.content.prefix(300)))\n\n"
            }
        }

        context += formatTasks(tasks)
        context += formatMemories(memories)

        return context
    }

    // MARK: - Connection Context

    /// Build context for discussing a connection between two notes from different threads.
    public func buildConnectionContext(
        noteA: Note, threadA: Thread?,
        noteB: Note, threadB: Thread?,
        relatedToA: [Note], relatedToB: [Note],
        tasks: [ThreadTask],
        memories: [ConversationMemory]
    ) -> String {
        var context = "## Note A: \(noteA.title)\n"
        context += "Thread: \(threadA?.name ?? "Unthreaded")\n\n"
        context += "\(noteA.content)\n\n"

        if let concepts = noteA.concepts, !concepts.isEmpty {
            context += "Concepts: \(concepts.joined(separator: ", "))\n"
        }

        context += "\n## Note B: \(noteB.title)\n"
        context += "Thread: \(threadB?.name ?? "Unthreaded")\n\n"
        context += "\(noteB.content)\n\n"

        if let concepts = noteB.concepts, !concepts.isEmpty {
            context += "Concepts: \(concepts.joined(separator: ", "))\n"
        }

        if let threadA = threadA {
            context += "\n## Thread: \(threadA.name)\n"
            if let summary = threadA.summary { context += "Summary: \(summary)\n" }
        }

        if let threadB = threadB {
            context += "\n## Thread: \(threadB.name)\n"
            if let summary = threadB.summary { context += "Summary: \(summary)\n" }
        }

        if !relatedToA.isEmpty {
            context += "\n## Notes Related to \(noteA.title)\n\n"
            for note in relatedToA.prefix(3) {
                context += "- \(note.title): \(String(note.content.prefix(150)))\n"
            }
        }

        if !relatedToB.isEmpty {
            context += "\n## Notes Related to \(noteB.title)\n\n"
            for note in relatedToB.prefix(3) {
                context += "- \(note.title): \(String(note.content.prefix(150)))\n"
            }
        }

        context += formatTasks(tasks)
        context += formatMemories(memories)

        return context
    }

    // MARK: - System Prompt

    /// Build system prompt for discuss-this chat sessions.
    public func buildSystemPrompt(for contextType: ContextType) -> String {
        let typeGuidance: String
        switch contextType {
        case .whatChanged:
            typeGuidance = "The user wants to discuss a specific note they recently wrote."
        case .needsAttention:
            typeGuidance = "The user wants to revisit a thread that has stalled or needs attention."
        case .connection:
            typeGuidance = "The user wants to explore a connection between two notes from different threads."
        }

        return """
        You are Selene. Minimal. Precise. Kind.
        You are a thinking partner for someone with ADHD. The user wants to discuss \
        something from their morning briefing.

        \(typeGuidance)

        Don't summarize it back to them. Start by asking a specific question or making \
        a specific observation. Be concrete — reference specific details from their notes.

        CONTEXT BLOCKS:
        You may receive labeled context like [EMOTIONAL HISTORY], [TASK HISTORY], [EMOTIONAL TREND], [THREAD STATE].
        Use these as evidence. Reference them naturally.
        """
    }

    // MARK: - Helpers

    private func formatTasks(_ tasks: [ThreadTask]) -> String {
        let openTasks = tasks.filter { !$0.isCompleted }
        guard !openTasks.isEmpty else { return "" }

        var result = "\n## Open Tasks\n\n"
        for task in openTasks {
            result += "- \(task.title ?? task.thingsTaskId)\n"
        }
        return result
    }

    private func formatMemories(_ memories: [ConversationMemory]) -> String {
        guard !memories.isEmpty else { return "" }

        var result = "\n## Conversation Memory\n\n"
        for memory in memories.prefix(5) {
            result += "- [\(memory.memoryType.rawValue)] \(memory.content)\n"
        }
        return result
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
