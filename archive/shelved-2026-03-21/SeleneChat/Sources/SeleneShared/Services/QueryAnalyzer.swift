import Foundation

/// Analyzes user queries to determine query type, extract keywords, and infer time scope
public class QueryAnalyzer {

    // MARK: - Types

    public enum QueryType {
        case pattern      // Trend/pattern detection: "what patterns...", "how often..."
        case search       // Find specific notes: "show me...", "find notes about..."
        case knowledge    // Answer from content: "what did I say...", "remind me..."
        case general      // Open-ended: "how am I doing"
        case thread       // Thread queries: "what's emerging", "show me X thread"
        case semantic     // Conceptual/meaning-based query
        case deepDive     // Thread deep-dive: "dig into X", "explore X thread"
        case synthesis    // Cross-thread synthesis: "what should I focus on?"
    }

    public enum TimeScope {
        case recent       // Last 7 days
        case thisWeek     // Current week
        case thisMonth    // Current month
        case allTime      // No time restriction
        case custom(from: Date, to: Date)
    }

    public enum ThreadQueryIntent {
        case listActive           // "what's emerging"
        case showSpecific(String) // "show me X thread"
    }

    public struct DeepDiveIntent {
        public let threadName: String

        public init(threadName: String) {
            self.threadName = threadName
        }
    }

    public struct AnalysisResult {
        public let queryType: QueryType
        public let keywords: [String]
        public let timeScope: TimeScope

        public init(queryType: QueryType, keywords: [String], timeScope: TimeScope) {
            self.queryType = queryType
            self.keywords = keywords
            self.timeScope = timeScope
        }
    }

    // MARK: - Detection Patterns

    private let patternIndicators = [
        "pattern", "trend", "often", "usually", "always", "frequently",
        "when do i", "how often", "what trends", "see patterns"
    ]

    private let searchIndicators = [
        "show", "find", "notes about", "list", "get", "search",
        "display", "where", "which notes"
    ]

    private let knowledgeIndicators = [
        "what did i", "remind me", "what was", "tell me about",
        "what have i", "did i mention", "what do i think"
    ]

    private let threadListIndicators = [
        "what's emerging", "whats emerging", "emerging threads",
        "active threads", "my threads", "show threads",
        "what threads", "thread overview"
    ]

    private let threadShowIndicators = [
        "show me", "tell me about", "what's the", "whats the",
        "details on", "more about"
    ]

    private let semanticIndicators = [
        "similar to",
        "related to",
        "like my",
        "conceptually",
        "meaning",
        "connects to",
        "associated with",
        "reminds me of",
        "in the spirit of",
        "along the lines of"
    ]

    private let deepDiveIndicators = [
        "dig into", "let's dig into", "lets dig into",
        "let's explore", "lets explore", "explore the",
        "help me think through", "think through the",
        "let's unpack", "lets unpack", "unpack the",
        "dive into", "deep dive into", "deep dive on"
    ]

    private let synthesisIndicators = [
        "what should i focus on",
        "what should i work on",
        "help me prioritize",
        "what's most important",
        "whats most important",
        "where should i put my energy",
        "what needs my attention",
        "what deserves my focus",
        "prioritize my threads",
        "what's the priority",
        "whats the priority"
    ]

    private let stopWords = Set([
        "a", "an", "the", "is", "are", "was", "were", "be", "been",
        "have", "has", "had", "do", "does", "did", "will", "would",
        "could", "should", "may", "might", "must", "can", "and", "or",
        "but", "in", "on", "at", "to", "for", "of", "with", "by",
        "from", "about", "as", "into", "through", "during", "before",
        "after", "above", "below", "between", "under", "i", "me", "my"
    ])

    // MARK: - Init

    public init() {}

    // MARK: - Public Methods

    public func analyze(_ query: String) -> AnalysisResult {
        let lowercased = query.lowercased()

        let queryType = detectQueryType(lowercased)
        let keywords = extractKeywords(from: lowercased)
        let timeScope = detectTimeScope(lowercased)

        return AnalysisResult(
            queryType: queryType,
            keywords: keywords,
            timeScope: timeScope
        )
    }

    /// Determine if a query should use semantic (vector) search
    public func shouldUseSemanticSearch(_ query: String) -> Bool {
        let queryType = detectQueryType(query.lowercased())

        switch queryType {
        case .semantic:
            return true
        case .knowledge, .general:
            // Use semantic for conceptual queries without specific keywords
            let keywords = extractKeywords(from: query.lowercased())
            return keywords.count <= 2  // Few keywords = more conceptual
        default:
            return false
        }
    }

    // MARK: - Private Detection Methods

    private func detectQueryType(_ query: String) -> QueryType {
        // Check synthesis before deep-dive (prioritization queries)
        if detectSynthesisIntent(query) {
            return .synthesis
        }

        // Check deep-dive queries (most specific)
        if detectDeepDiveIntent(query) != nil {
            return .deepDive
        }

        // Check thread queries next
        if detectThreadIntent(query) != nil {
            return .thread
        }

        // Check pattern indicators
        for indicator in patternIndicators {
            if query.contains(indicator) {
                return .pattern
            }
        }

        // Check knowledge indicators
        for indicator in knowledgeIndicators {
            if query.contains(indicator) {
                return .knowledge
            }
        }

        // Check search indicators
        for indicator in searchIndicators {
            if query.contains(indicator) {
                return .search
            }
        }

        // Check for semantic queries
        for indicator in semanticIndicators {
            if query.contains(indicator) {
                return .semantic
            }
        }

        // Also treat vague conceptual queries as semantic
        if query.hasPrefix("what about") ||
           query.hasPrefix("thoughts on") ||
           query.hasPrefix("anything about") {
            return .semantic
        }

        // Default to general for open-ended questions
        return .general
    }

    private func extractKeywords(from query: String) -> [String] {
        // Split on whitespace and punctuation
        let words = query.components(separatedBy: CharacterSet.alphanumerics.inverted)

        // Filter out stop words and empty strings
        let keywords = words.filter { word in
            !word.isEmpty && !stopWords.contains(word.lowercased())
        }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        return keywords.filter { word in
            if seen.contains(word) {
                return false
            } else {
                seen.insert(word)
                return true
            }
        }
    }

    private func detectTimeScope(_ query: String) -> TimeScope {
        // Check for specific time indicators
        if query.contains("recent") || query.contains("lately") || query.contains("recently") {
            return .recent
        }

        if query.contains("this week") {
            return .thisWeek
        }

        if query.contains("this month") {
            return .thisMonth
        }

        if query.contains("today") {
            return .custom(from: Calendar.current.startOfDay(for: Date()), to: Date())
        }

        if query.contains("yesterday") {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            let startOfYesterday = Calendar.current.startOfDay(for: yesterday)
            let endOfYesterday = Calendar.current.date(byAdding: .day, value: 1, to: startOfYesterday)!
            return .custom(from: startOfYesterday, to: endOfYesterday)
        }

        // Default to all time if no time scope specified
        return .allTime
    }

    /// Detect if query is thread-related and extract intent
    public func detectThreadIntent(_ query: String) -> ThreadQueryIntent? {
        let lowercased = query.lowercased()

        // Check for list queries first
        for indicator in threadListIndicators {
            if lowercased.contains(indicator) {
                return .listActive
            }
        }

        // Check for specific thread queries
        // Pattern: "show me X thread" or "X thread"
        if lowercased.contains("thread") {
            // Try to extract thread name
            if let name = extractThreadName(from: lowercased) {
                return .showSpecific(name)
            }
        }

        return nil
    }

    /// Detect if query is a deep-dive request and extract the thread name
    public func detectDeepDiveIntent(_ query: String) -> DeepDiveIntent? {
        let lowercased = query.lowercased()

        // Check if query contains any deep-dive indicators
        for indicator in deepDiveIndicators {
            if lowercased.contains(indicator) {
                // Extract thread name after the indicator
                if let range = lowercased.range(of: indicator) {
                    var threadName = String(lowercased[range.upperBound...])
                        .trimmingCharacters(in: .whitespaces)

                    // Remove trailing "thread" if present
                    if threadName.hasSuffix(" thread") {
                        threadName = String(threadName.dropLast(7))
                            .trimmingCharacters(in: .whitespaces)
                    }

                    // Remove leading "the" if present
                    if threadName.hasPrefix("the ") {
                        threadName = String(threadName.dropFirst(4))
                            .trimmingCharacters(in: .whitespaces)
                    }

                    // Only return if we extracted a short, noun-phrase thread name
                    // Real thread names are 1-5 words, not questions or clauses
                    let wordCount = threadName.split(separator: " ").count
                    let clauseStarters = ["what", "when", "where", "why", "how", "if", "whether", "that", "which"]
                    let startsWithClause = clauseStarters.contains(where: { threadName.hasPrefix($0 + " ") || threadName == $0 })
                    if !threadName.isEmpty && wordCount <= 5 && !startsWithClause {
                        return DeepDiveIntent(threadName: threadName)
                    }
                }
            }
        }

        return nil
    }

    /// Detect if query is a synthesis/prioritization request
    public func detectSynthesisIntent(_ query: String) -> Bool {
        let lowercased = query.lowercased()
        for indicator in synthesisIndicators {
            if lowercased.contains(indicator) {
                return true
            }
        }
        return false
    }

    private func extractThreadName(from query: String) -> String? {
        // Pattern 1: "show me [name] thread"
        let showPattern = #"(?:show me|tell me about|what's the|whats the|details on|more about)\s+(?:the\s+)?(.+?)\s+thread"#
        if let regex = try? NSRegularExpression(pattern: showPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range(at: 1), in: query) {
            return String(query[range]).trimmingCharacters(in: .whitespaces)
        }

        // Pattern 2: "[name] thread" at end of query
        let endPattern = #"(.+?)\s+thread\s*$"#
        if let regex = try? NSRegularExpression(pattern: endPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)),
           let range = Range(match.range(at: 1), in: query) {
            let name = String(query[range]).trimmingCharacters(in: .whitespaces)
            // Filter out common false positives
            let falsePositives = ["the", "a", "my", "this", "that", "any"]
            if !falsePositives.contains(name.lowercased()) {
                return name
            }
        }

        return nil
    }
}

// MARK: - CustomStringConvertible

extension QueryAnalyzer.QueryType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pattern: return "pattern"
        case .search: return "search"
        case .knowledge: return "knowledge"
        case .general: return "general"
        case .thread: return "thread"
        case .semantic: return "semantic"
        case .deepDive: return "deep-dive"
        case .synthesis: return "synthesis"
        }
    }
}

extension QueryAnalyzer.TimeScope: CustomStringConvertible {
    public var description: String {
        switch self {
        case .recent: return "recent (last 7 days)"
        case .thisWeek: return "this week"
        case .thisMonth: return "this month"
        case .allTime: return "all time"
        case .custom(let from, let to):
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return "custom (\(formatter.string(from: from)) - \(formatter.string(from: to)))"
        }
    }
}
