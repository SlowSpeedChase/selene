import Foundation

/// Builds prompts for thread workspace chat conversations.
/// Similar to DeepDivePromptBuilder but includes task state context.
public class ThreadWorkspacePromptBuilder {

    private let contextBuilder = ThinkingPartnerContextBuilder()

    // MARK: - System Identity

    private let systemIdentity = """
    You are Selene. Minimal. Precise. Kind.

    You are an interactive thinking partner for someone with ADHD.

    RULES:
    - Never summarize the thread unless asked. The user can see it.
    - If they ask for help: ask 1-2 questions first. What are they stuck on?
    - Cite specific notes by content. Never reference notes generically.
    - Present 2-3 options with tradeoffs when they face a decision.
    - If context shows repeated patterns or failed attempts: name them. Kindly.
    - End by asking what resonates.

    CONTEXT BLOCKS:
    You may receive labeled context like [EMOTIONAL HISTORY], [TASK HISTORY], [EMOTIONAL TREND], [THREAD STATE].
    Use these as evidence. Reference them naturally.

    CAPABILITIES:
    - Create tasks in Things via action markers when you and the user have collaboratively identified concrete next steps:
      [ACTION: Brief description | ENERGY: high/medium/low | TIMEFRAME: today/this-week/someday]
    - Full access to the user's notes, thread history, and existing tasks
    """

    // MARK: - Init

    public init() {}

    // MARK: - Initial Prompt

    /// Build the initial prompt for a workspace chat session.
    /// - Parameters:
    ///   - thread: The thread being worked on
    ///   - notes: Notes belonging to this thread
    ///   - tasks: Current tasks linked to this thread
    /// - Returns: A formatted prompt string for the LLM
    public func buildInitialPrompt(thread: Thread, notes: [Note], tasks: [ThreadTask]) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)
        let taskContext = buildTaskContext(tasks)

        return """
        \(systemIdentity)

        ## Thread: "\(thread.name)"

        \(threadContext)

        \(taskContext)
        """
    }

    // MARK: - Follow-Up Prompt

    /// Build a follow-up prompt that includes conversation history and current task state.
    /// - Parameters:
    ///   - thread: The thread being worked on
    ///   - notes: Notes belonging to this thread
    ///   - tasks: Current tasks linked to this thread
    ///   - conversationHistory: Previous exchanges in this session
    ///   - currentQuery: The user's current question
    /// - Returns: A formatted prompt string for the LLM
    public func buildFollowUpPrompt(
        thread: Thread,
        notes: [Note],
        tasks: [ThreadTask],
        conversationHistory: String,
        currentQuery: String
    ) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)
        let taskContext = buildTaskContext(tasks)

        return """
        \(systemIdentity)

        ## Thread: "\(thread.name)"

        \(threadContext)

        \(taskContext)

        ## Conversation So Far
        \(conversationHistory)

        ## Current Question
        \(currentQuery)
        """
    }

    // MARK: - Task Context

    private func buildTaskContext(_ tasks: [ThreadTask]) -> String {
        guard !tasks.isEmpty else {
            return "## Current Tasks\nNo tasks linked to this thread yet."
        }

        let openTasks = tasks.filter { !$0.isCompleted }
        let completedTasks = tasks.filter { $0.isCompleted }

        var context = "## Current Tasks (\(openTasks.count) open, \(completedTasks.count) completed)\n"

        for task in openTasks {
            let title = task.title ?? task.thingsTaskId
            context += "- [ ] \(title)\n"
        }

        for task in completedTasks {
            let title = task.title ?? task.thingsTaskId
            context += "- [x] \(title)\n"
        }

        return context
    }

    // MARK: - Chunk-Based Prompts

    /// Build the initial prompt using retrieved chunks instead of full notes.
    /// - Parameters:
    ///   - thread: The thread being worked on
    ///   - retrievedChunks: Semantically relevant chunks with similarity scores
    ///   - tasks: Current tasks linked to this thread
    /// - Returns: A formatted prompt string for the LLM
    public func buildInitialPromptWithChunks(
        thread: Thread,
        retrievedChunks: [(chunk: NoteChunk, similarity: Float)],
        tasks: [ThreadTask]
    ) -> String {
        let chunkContext = formatChunkContext(thread: thread, chunks: retrievedChunks)
        let taskContext = buildTaskContext(tasks)

        return """
        \(systemIdentity)

        \(chunkContext)

        \(taskContext)
        """
    }

    /// Build a follow-up prompt with pinned chunks from prior turns and newly retrieved chunks.
    /// - Parameters:
    ///   - thread: The thread being worked on
    ///   - pinnedChunks: Chunks referenced in prior conversation turns (preserves context)
    ///   - retrievedChunks: Newly retrieved chunks for the current query
    ///   - tasks: Current tasks linked to this thread
    ///   - conversationHistory: Previous exchanges in this session
    ///   - currentQuery: The user's current question
    /// - Returns: A formatted prompt string for the LLM
    public func buildFollowUpPromptWithChunks(
        thread: Thread,
        pinnedChunks: [(chunk: NoteChunk, similarity: Float)],
        retrievedChunks: [(chunk: NoteChunk, similarity: Float)],
        tasks: [ThreadTask],
        conversationHistory: String,
        currentQuery: String
    ) -> String {
        let chunkContext = formatChunkContext(thread: thread, chunks: pinnedChunks + retrievedChunks)
        let taskContext = buildTaskContext(tasks)

        return """
        \(systemIdentity)

        \(chunkContext)

        \(taskContext)

        ## Conversation So Far
        \(conversationHistory)

        ## Current Question
        \(currentQuery)
        """
    }

    /// Format retrieved chunks into context for the prompt, deduplicating by chunk ID.
    private func formatChunkContext(thread: Thread, chunks: [(chunk: NoteChunk, similarity: Float)]) -> String {
        var context = "## Thread: \(thread.name)\n"
        context += "Status: \(thread.status) \(thread.statusEmoji) | Notes: \(thread.noteCount)\n"

        if let why = thread.why, !why.isEmpty {
            context += "Why: \(why)\n"
        }

        context += "\n## Relevant Context\n\n"

        var seen = Set<Int64>()
        for item in chunks {
            guard !seen.contains(item.chunk.id) else { continue }
            seen.insert(item.chunk.id)

            if let topic = item.chunk.topic {
                context += "**[\(topic)]**\n"
            }
            context += "\(item.chunk.content)\n\n"
        }

        return context
    }

    // MARK: - What's Next

    /// Patterns that indicate a "what's next" query
    private let whatsNextPatterns: [String] = [
        "what's next",
        "whats next",
        "what should i do",
        "what should i work on",
        "what do i do",
        "what to do next",
        "what now",
        "next step",
        "next steps",
        "what should i focus on",
        "what needs my attention",
        "what needs attention",
        "what's most important",
        "whats most important",
        "what am i missing",
        "what's stalled",
        "whats stalled",
        "what's stuck",
        "whats stuck",
        "where should i focus",
        "what deserves energy",
    ]

    /// Detect if a query is asking "what's next"
    public func isWhatsNextQuery(_ query: String) -> Bool {
        let lowered = query.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespaces)
        return whatsNextPatterns.contains { lowered.contains($0) }
    }

    // MARK: - Planning Intent Detection

    /// Patterns that indicate a planning/help intent (broader than "what's next")
    private let planningPatterns: [String] = [
        "help me", "can you help",
        "make a plan", "create a plan", "come up with a plan",
        "help me plan", "build a plan",
        "break this down", "break it down",
        "lay out the steps", "map this out", "map out",
        "how should i approach", "how do i tackle",
        "where do i start", "where should i start",
        "what are my options", "decide between", "help me decide",
        "what should i do about", "which should i",
        "think through", "work through", "figure out",
        "think about this", "reason through",
        "prioritize", "what matters most", "most important",
        "next move", "what to tackle",
        "i'm stuck", "im stuck",
        "i don't know where to start", "don't know where to start",
        "what would you recommend",
        "talk me through",
        "i'm overwhelmed", "im overwhelmed",
        "i keep putting this off", "keep avoiding", "why am i avoiding",
        "what's the simplest", "simplest first step",
        "how do i even begin", "how do i begin",
        "break this into pieces", "break this into steps",
        "what's blocking", "what blocks", "where's the resistance",
    ]

    /// Detect if a query has planning/help intent (distinct from "what's next").
    public func isPlanningQuery(_ query: String) -> Bool {
        let lowered = query.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespaces)
        return planningPatterns.contains { lowered.contains($0) }
    }

    /// Build a planning-specific prompt that coaches multi-turn clarifying dialogue.
    /// Used when `isPlanningQuery` returns true.
    public func buildPlanningPrompt(
        thread: Thread,
        notes: [Note],
        tasks: [ThreadTask],
        userQuery: String
    ) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)
        let taskContext = buildTaskContext(tasks)

        return """
        \(systemIdentity)

        ## Thread: "\(thread.name)"

        \(threadContext)

        \(taskContext)

        ## User's Request
        \(userQuery)

        FOCUS:
        Start by asking 1-2 short clarifying questions about priorities, constraints, or what success looks like. Do NOT jump to a full plan.

        After the user answers:
        1. Identify 2-3 possible directions with trade-offs
        2. Ask which resonates
        3. Break the chosen direction into concrete steps
        4. Suggest tasks via action markers
        """
    }

    /// Build a specialized prompt for "what's next" recommendations
    public func buildWhatsNextPrompt(thread: Thread, notes: [Note], tasks: [ThreadTask]) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)
        let openTasks = tasks.filter { !$0.isCompleted }
        let completedTasks = tasks.filter { $0.isCompleted }

        var taskList = ""
        if !openTasks.isEmpty {
            taskList += "Open tasks:\n"
            for task in openTasks {
                let title = task.title ?? task.thingsTaskId
                let age = Calendar.current.dateComponents([.day], from: task.createdAt, to: Date()).day ?? 0
                taskList += "- \(title) (created \(age) days ago)\n"
            }
        }
        if !completedTasks.isEmpty {
            taskList += "\nRecently completed:\n"
            for task in completedTasks.prefix(5) {
                let title = task.title ?? task.thingsTaskId
                taskList += "- \(title) (done)\n"
            }
        }

        return """
        \(systemIdentity)

        ## Thread: "\(thread.name)"

        \(threadContext)

        ## Task State
        \(taskList.isEmpty ? "No tasks linked to this thread yet." : taskList)

        FOCUS:
        Based on thread context, open tasks, and what's been completed:
        1. Propose 2-3 possible directions, each with a brief trade-off (energy, impact, dependencies)
        2. Ask which resonates right now
        3. Do NOT pick for them

        If no open tasks exist, suggest logical next actions based on the thread's current state.
        """
    }
}
