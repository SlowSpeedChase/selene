import Foundation

/// Orchestrates multi-signal retrieval for chat context.
/// Assembles labeled context blocks from emotional history, task outcomes,
/// sentiment trends, and thread state.
public class ContextualRetriever {
    private let dataProvider: DataProvider
    private let tokenBudget: Int

    public init(dataProvider: DataProvider, tokenBudget: Int = 3000) {
        self.dataProvider = dataProvider
        self.tokenBudget = tokenBudget
    }

    /// Retrieve contextual blocks for a query.
    public func retrieve(
        query: String,
        keywords: [String],
        threadId: Int64? = nil
    ) async throws -> RetrievedContext {
        var blocks: [ContextBlock] = []
        var remainingTokens = tokenBudget

        // 1. Emotional history — notes with strong emotion on this topic
        let emotionalNotes = try await dataProvider.getEmotionalNotes(
            keywords: keywords, limit: 3
        )
        for note in emotionalNotes {
            let block = ContextBlock(
                type: .emotionalHistory,
                content: note.essence ?? String(note.content.prefix(200)),
                sourceDate: note.createdAt,
                sourceTitle: note.title
            )
            let tokens = block.formatted.count / 4
            guard remainingTokens - tokens > 0 else { break }
            blocks.append(block)
            remainingTokens -= tokens
        }

        // 2. Task outcomes — completed/abandoned tasks related to topic
        let taskOutcomes = try await dataProvider.getTaskOutcomes(
            keywords: keywords, limit: 5
        )
        if !taskOutcomes.isEmpty {
            let summary = taskOutcomes.map { outcome in
                let statusLabel = outcome.status == "completed" ? "done" : outcome.status
                return "\(outcome.taskTitle) (\(statusLabel), \(outcome.daysOpen)d)"
            }.joined(separator: "; ")

            let block = ContextBlock(type: .taskHistory, content: summary)
            let tokens = block.formatted.count / 4
            if remainingTokens - tokens > 0 {
                blocks.append(block)
                remainingTokens -= tokens
            }
        }

        // 3. Sentiment trend — emotional distribution this week
        let trend = try await dataProvider.getSentimentTrend(days: 7)
        if trend.totalNotes > 0 {
            let block = ContextBlock(
                type: .sentimentTrend,
                content: "This week (\(trend.totalNotes) notes): \(trend.formatted)"
            )
            let tokens = block.formatted.count / 4
            if remainingTokens - tokens > 0 {
                blocks.append(block)
                remainingTokens -= tokens
            }
        }

        // 4. Thread state — if scoped to a thread
        if let threadId = threadId,
           let thread = try await dataProvider.getThreadById(threadId) {
            let tasks = try await dataProvider.getTasksForThread(threadId)
            let openTasks = tasks.filter { !$0.isCompleted }
            let daysSinceActivity = thread.lastActivityAt.map {
                Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
            } ?? 0

            let block = ContextBlock(
                type: .threadState,
                content: "'\(thread.name)' \u{2014} \(thread.status), \(thread.noteCount) notes, \(openTasks.count) open tasks, last activity \(daysSinceActivity)d ago, momentum \(thread.momentumDisplay)"
            )
            let tokens = block.formatted.count / 4
            if remainingTokens - tokens > 0 {
                blocks.append(block)
                remainingTokens -= tokens
            }
        }

        return RetrievedContext(blocks: blocks)
    }
}
