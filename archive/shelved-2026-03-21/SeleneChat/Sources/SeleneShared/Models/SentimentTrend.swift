import Foundation

/// Aggregated emotional tone distribution over a time window
public struct SentimentTrend: Hashable {
    /// e.g. ["frustrated": 4, "anxious": 2, "calm": 1]
    public let toneCounts: [String: Int]
    public let totalNotes: Int
    public let averageSentimentScore: Double?
    public let periodDays: Int

    public init(toneCounts: [String: Int], totalNotes: Int,
                averageSentimentScore: Double?, periodDays: Int) {
        self.toneCounts = toneCounts
        self.totalNotes = totalNotes
        self.averageSentimentScore = averageSentimentScore
        self.periodDays = periodDays
    }

    /// Most frequent non-neutral tone, if any
    public var dominantTone: String? {
        toneCounts.filter { $0.key != "neutral" }.max(by: { $0.value < $1.value })?.key
    }

    /// Format for context injection: "frustrated 4x, anxious 2x"
    public var formatted: String {
        let sorted = toneCounts.filter { $0.key != "neutral" }
            .sorted { $0.value > $1.value }
        guard !sorted.isEmpty else { return "mostly neutral" }
        return sorted.map { "\($0.key) \($0.value)x" }.joined(separator: ", ")
    }
}
