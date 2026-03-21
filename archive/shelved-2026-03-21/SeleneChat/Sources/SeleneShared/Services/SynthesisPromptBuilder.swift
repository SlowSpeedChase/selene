import Foundation

/// Builds specialized prompts for cross-thread synthesis and prioritization queries
public class SynthesisPromptBuilder {
    private let contextBuilder = ThinkingPartnerContextBuilder()

    // MARK: - Init

    public init() {}

    // MARK: - Public Methods

    /// Build a synthesis prompt for cross-thread prioritization
    /// - Parameters:
    ///   - threads: Active threads to consider for prioritization
    ///   - notesPerThread: Recent notes organized by thread ID
    /// - Returns: A complete prompt for the LLM
    public func buildSynthesisPrompt(threads: [Thread], notesPerThread: [Int64: [Note]]) -> String {
        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        return buildPromptWithContext(context: context, conversationHistory: nil, currentQuery: nil)
    }

    /// Build a synthesis prompt with conversation history for follow-up queries
    /// - Parameters:
    ///   - threads: Active threads to consider for prioritization
    ///   - notesPerThread: Recent notes organized by thread ID
    ///   - conversationHistory: Previous conversation turns
    ///   - currentQuery: The user's current question
    /// - Returns: A complete prompt for the LLM
    public func buildSynthesisPromptWithHistory(
        threads: [Thread],
        notesPerThread: [Int64: [Note]],
        conversationHistory: String,
        currentQuery: String
    ) -> String {
        let context = contextBuilder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        return buildPromptWithContext(context: context, conversationHistory: conversationHistory, currentQuery: currentQuery)
    }

    // MARK: - Private Methods

    private func buildPromptWithContext(context: String, conversationHistory: String?, currentQuery: String?) -> String {
        var prompt = """
        You are Selene. Minimal. Precise. Kind.
        You are a thinking partner for someone with ADHD. Your role is to help them make decisions about where to focus their energy.

        \(context)

        ## Your Task

        Based on these threads, help prioritize where to focus:

        1. **Identify momentum** - Which threads have energy and recent activity?
        2. **Note tensions** - Any threads pulling in different directions?
        3. **Find connections** - How might threads relate to each other?
        4. **Suggest focus** - Present 2-3 options with tradeoffs. Ask which resonates.
        5. **Offer to go deeper** - Ask if they want to explore any thread further

        CONTEXT BLOCKS:
        You may receive labeled context like [EMOTIONAL HISTORY], [TASK HISTORY], [EMOTIONAL TREND], [THREAD STATE].
        Use these as evidence. Reference them naturally.

        ## Guidelines

        - Be direct. Make a specific recommendation, but present it as one option among 2-3.
        - Consider thread momentum, urgency, and cognitive load
        - Every word earns its place.

        """

        if let history = conversationHistory, !history.isEmpty {
            prompt += """

            ## Conversation History

            \(history)

            """
        }

        if let query = currentQuery, !query.isEmpty {
            prompt += """

            ## Current Question

            \(query)
            """
        }

        return prompt
    }
}
