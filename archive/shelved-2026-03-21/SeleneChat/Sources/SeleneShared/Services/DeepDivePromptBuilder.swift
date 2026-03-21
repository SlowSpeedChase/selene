import Foundation

/// Builds specialized prompts for thread deep-dive conversations.
/// Uses ADHD-friendly framing and includes action marker instructions.
public class DeepDivePromptBuilder {

    private let contextBuilder = ThinkingPartnerContextBuilder()

    // MARK: - Action Marker Format

    /// Standard action marker format for LLM responses
    private let actionMarkerFormat = """
    When suggesting actions, use this format:
    [ACTION: Brief action description | ENERGY: high/medium/low | TIMEFRAME: today/this-week/someday]
    """

    // MARK: - Init

    public init() {}

    // MARK: - Initial Prompt

    /// Build the initial prompt for starting a deep-dive into a thread.
    /// - Parameters:
    ///   - thread: The thread to explore
    ///   - notes: The notes belonging to this thread
    /// - Returns: A formatted prompt string for the LLM
    public func buildInitialPrompt(thread: Thread, notes: [Note]) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)

        return """
        You are Selene. Minimal. Precise. Kind.
        You are a thinking partner for someone with ADHD, helping them explore their ideas about "\(thread.name)".

        \(threadContext)

        FOCUS:
        1. Synthesize the key ideas across these notes
        2. Identify any tensions or contradictions in the thinking
        3. Ask 1-2 clarifying questions to help deepen understanding

        CONTEXT BLOCKS:
        You may receive labeled context like [EMOTIONAL HISTORY], [TASK HISTORY], [EMOTIONAL TREND], [THREAD STATE].
        Use these as evidence. Reference them naturally.

        \(actionMarkerFormat)

        Focus on insight, not summary. Every word earns its place.
        """
    }

    // MARK: - Follow-Up Prompt

    /// Build a follow-up prompt that includes conversation history.
    /// - Parameters:
    ///   - thread: The thread being explored
    ///   - notes: The notes belonging to this thread
    ///   - conversationHistory: Previous exchanges in this deep-dive session
    ///   - currentQuery: The user's current question
    /// - Returns: A formatted prompt string for the LLM
    public func buildFollowUpPrompt(
        thread: Thread,
        notes: [Note],
        conversationHistory: String,
        currentQuery: String
    ) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)

        return """
        You are Selene. Minimal. Precise. Kind.
        You are a thinking partner for someone with ADHD, continuing a deep-dive into "\(thread.name)".

        \(threadContext)

        ## Conversation So Far
        \(conversationHistory)

        ## Current Question
        \(currentQuery)

        \(actionMarkerFormat)

        Be direct and specific. Every word earns its place.
        """
    }
}
