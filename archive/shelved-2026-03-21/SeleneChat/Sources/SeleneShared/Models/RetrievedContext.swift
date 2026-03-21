import Foundation

public enum ContextBlockType: String, Hashable {
    case relevantNote = "RELEVANT NOTE"
    case emotionalHistory = "EMOTIONAL HISTORY"
    case decisionHistory = "DECISION"
    case taskHistory = "TASK HISTORY"
    case sentimentTrend = "EMOTIONAL TREND"
    case threadState = "THREAD STATE"
}

public struct ContextBlock: Hashable {
    public let type: ContextBlockType
    public let content: String
    public let sourceDate: Date?
    public let sourceTitle: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    public init(type: ContextBlockType, content: String,
                sourceDate: Date? = nil, sourceTitle: String? = nil) {
        self.type = type
        self.content = content
        self.sourceDate = sourceDate
        self.sourceTitle = sourceTitle
    }

    public var formatted: String {
        let dateStr: String
        if let date = sourceDate {
            dateStr = " - \(Self.dateFormatter.string(from: date))"
        } else {
            dateStr = ""
        }
        let titleStr = sourceTitle.map { " \u{2014} \($0)" } ?? ""
        return "[\(type.rawValue)\(dateStr)\(titleStr)]: \(content)"
    }
}

public struct RetrievedContext {
    public let blocks: [ContextBlock]

    public init(blocks: [ContextBlock]) {
        self.blocks = blocks
    }

    /// Format all blocks for prompt injection
    public func formatted() -> String {
        blocks.map { $0.formatted }.joined(separator: "\n")
    }

    /// Estimate token count (4 chars per token)
    public var estimatedTokens: Int {
        formatted().count / 4
    }
}
