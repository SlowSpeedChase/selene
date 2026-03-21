import Foundation

/// Query types for Thinking Partner modes
public enum ThinkingPartnerQueryType: String {
    case briefing   // Morning briefing - threads + momentum
    case synthesis  // Cross-thread prioritization
    case deepDive   // Single thread exploration

    /// Token budget for context assembly
    public var tokenBudget: Int {
        switch self {
        case .briefing: return 1500
        case .synthesis: return 2000
        case .deepDive: return 8000
        }
    }

    /// Description for debugging
    public var description: String {
        switch self {
        case .briefing: return "Morning Briefing"
        case .synthesis: return "Cross-Thread Synthesis"
        case .deepDive: return "Thread Deep-Dive"
        }
    }
}
