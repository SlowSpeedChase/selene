import Foundation

/// Manages conversation context for LLM prompts
public struct SessionContext {
    public let messages: [Message]

    /// Maximum tokens to allocate for conversation history
    public static let maxHistoryTokens = 2000

    /// Number of recent turns to keep verbatim (1 turn = user + assistant)
    public static let recentTurnsVerbatim = 4

    public init(messages: [Message]) {
        self.messages = messages
    }

    /// Format messages for inclusion in LLM prompt
    public var formattedHistory: String {
        guard !messages.isEmpty else { return "" }

        return messages.map { message in
            let role = message.role == .user ? "User" : "Selene"
            return "\(role): \(message.content)"
        }.joined(separator: "\n\n")
    }

    /// Rough token estimate (4 chars per token)
    public var estimatedTokens: Int {
        let totalChars = formattedHistory.count
        return totalChars / 4
    }

    /// Get history truncated to fit within token limit, preserving recent messages
    public func truncatedHistory(maxTokens: Int) -> String {
        guard !messages.isEmpty else { return "" }

        var result: [String] = []
        var currentTokens = 0

        // Process messages from most recent to oldest
        for message in messages.reversed() {
            let role = message.role == .user ? "User" : "Selene"
            let formatted = "\(role): \(message.content)"
            let messageTokens = formatted.count / 4

            if currentTokens + messageTokens > maxTokens {
                break
            }

            result.insert(formatted, at: 0)
            currentTokens += messageTokens
        }

        return result.joined(separator: "\n\n")
    }

    /// Get history with older messages compressed to fit within token budget.
    /// Recent turns are kept verbatim; older messages are truncated to 100 chars each.
    /// - Parameter recentTurnCount: Number of recent message pairs to keep verbatim
    public func historyWithSummary(recentTurnCount: Int = SessionContext.recentTurnsVerbatim) -> String {
        guard !messages.isEmpty else { return "" }

        let recentMessageCount = recentTurnCount * 2  // user + assistant per turn

        // If we have few enough messages, just return them all
        if messages.count <= recentMessageCount {
            return formattedHistory
        }

        // Split into old and recent
        let olderMessages = Array(messages.prefix(messages.count - recentMessageCount))
        let recentMessages = Array(messages.suffix(recentMessageCount))

        // Format recent messages verbatim
        let recentFormatted = recentMessages.map { message in
            let role = message.role == .user ? "User" : "Selene"
            return "\(role): \(message.content)"
        }.joined(separator: "\n\n")

        // Calculate remaining char budget for older messages
        let maxChars = SessionContext.maxHistoryTokens * 4
        let headerOverhead = 40 // "[Earlier in conversation:]\n\n" + "[Recent:]\n\n"
        let remainingBudget = maxChars - recentFormatted.count - headerOverhead

        if remainingBudget <= 0 || olderMessages.isEmpty {
            return recentFormatted
        }

        // Compress older messages: truncate each to 100 chars, stop when budget exhausted
        let olderCompressed = compressMessages(olderMessages, maxChars: remainingBudget)

        if olderCompressed.isEmpty {
            return recentFormatted
        }

        return "[Earlier in conversation:]\n\n\(olderCompressed)\n\n[Recent:]\n\n\(recentFormatted)"
    }

    /// Compress messages by truncating each to a maximum character count,
    /// stopping when the total character budget is exhausted.
    private func compressMessages(_ messages: [Message], maxChars: Int) -> String {
        let maxCharsPerMessage = 100
        var lines: [String] = []
        var totalChars = 0

        for message in messages {
            let role = message.role == .user ? "User" : "Selene"
            if message.role == .system { continue }

            var content = message.content
            if content.count > maxCharsPerMessage {
                content = String(content.prefix(maxCharsPerMessage - 3)) + "..."
            }

            let line = "\(role): \(content)"
            let lineChars = line.count + 2 // +2 for "\n\n" separator

            if totalChars + lineChars > maxChars { break }

            lines.append(line)
            totalChars += lineChars
        }

        return lines.joined(separator: "\n\n")
    }
}
