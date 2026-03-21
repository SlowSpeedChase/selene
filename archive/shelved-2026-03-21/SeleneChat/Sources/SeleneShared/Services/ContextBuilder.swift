import Foundation

/// Builds optimal context strings for Ollama based on query type and available notes
public class ContextBuilder {

    // MARK: - Init

    public init() {}

    // MARK: - Public Methods

    /// Build context string adapted to query type
    public func buildContext(notes: [Note], queryType: QueryAnalyzer.QueryType) -> String {
        switch queryType {
        case .pattern:
            return buildMetadataContext(notes)
        case .search:
            return buildSummaryContext(notes)
        case .knowledge:
            return buildFullContext(notes)
        case .general:
            return buildFullContext(notes)
        case .thread:
            return buildSummaryContext(notes)  // Thread queries use summary context
        case .semantic:
            return buildFullContext(notes)  // Semantic queries need full content for conceptual understanding
        case .deepDive:
            return buildFullContext(notes)  // Deep-dive needs full content for analysis
        case .synthesis:
            return buildSummaryContext(notes)  // Synthesis uses summary context across threads
        }
    }

    // MARK: - Private Context Builders

    /// Metadata only - optimized for pattern detection (100+ notes)
    /// Format: Title, date, concepts, themes, sentiment, energy
    private func buildMetadataContext(_ notes: [Note]) -> String {
        var context = ""

        for (index, note) in notes.enumerated() {
            context += "Note \(index + 1): \"\(note.title)\" (\(formatDate(note.createdAt)))\n"

            if let concepts = note.concepts, !concepts.isEmpty {
                context += "- Concepts: \(concepts.joined(separator: ", "))\n"
            }

            if let theme = note.primaryTheme {
                context += "- Theme: \(theme)\n"
            }

            if let sentiment = note.overallSentiment, let score = note.sentimentScore {
                context += "- Sentiment: \(sentiment) (\(String(format: "%.1f", score)))\n"
            }

            if let energy = note.energyLevel {
                context += "- Energy: \(energy)\n"
            }

            if let event = note.calendarEvent {
                context += "- Calendar: \(event.title)\n"
            }

            context += "\n"
        }

        return context
    }

    /// Summary context - title + preview + metadata (30-50 notes)
    /// Includes first 200 characters of content
    private func buildSummaryContext(_ notes: [Note]) -> String {
        var context = ""

        for (index, note) in notes.enumerated() {
            context += "Note \(index + 1): \"\(note.title)\" (\(formatDate(note.createdAt)))\n"

            // Add content preview (first 200 chars)
            let preview = String(note.content.prefix(200))
            let cleanPreview = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            context += "Content: \"\(cleanPreview)...\"\n"

            if let event = note.calendarEvent {
                context += "- Calendar: \(event.title) (\(event.formattedTimeRange))\n"
            }

            if let concepts = note.concepts, !concepts.isEmpty {
                context += "- Concepts: \(concepts.joined(separator: ", "))\n"
            }

            if let theme = note.primaryTheme {
                context += "- Theme: \(theme)\n"
            }

            context += "\n"
        }

        return context
    }

    /// Full context - complete content + all metadata (5-15 notes)
    /// For deep knowledge queries requiring full understanding
    private func buildFullContext(_ notes: [Note]) -> String {
        var context = ""

        for (index, note) in notes.enumerated() {
            context += "Note \(index + 1): \"\(note.title)\" (\(formatDate(note.createdAt)))\n"
            if let event = note.calendarEvent {
                context += "Calendar Context: Written during \"\(event.title)\" (\(event.formattedTimeRange))\n"
            }
            context += "Full Content:\n"
            context += "\"\(note.content)\"\n\n"

            if let concepts = note.concepts, !concepts.isEmpty {
                context += "- Concepts: \(concepts.joined(separator: ", "))\n"
            }

            if let theme = note.primaryTheme {
                context += "- Theme: \(theme)\n"
            }

            if let secondaryThemes = note.secondaryThemes, !secondaryThemes.isEmpty {
                context += "- Secondary Themes: \(secondaryThemes.joined(separator: ", "))\n"
            }

            if let sentiment = note.overallSentiment, let score = note.sentimentScore {
                context += "- Sentiment: \(sentiment) (\(String(format: "%.2f", score)))\n"
            }

            if let tone = note.emotionalTone {
                context += "- Emotional Tone: \(tone)\n"
            }

            if let energy = note.energyLevel {
                context += "- Energy: \(energy)\n"
            }

            context += "\n---\n\n"
        }

        return context
    }

    // MARK: - Helper Methods

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Estimate context size in tokens (rough: 1 token ~ 4 characters)
    public func estimateTokenCount(for context: String) -> Int {
        return context.count / 4
    }
}
