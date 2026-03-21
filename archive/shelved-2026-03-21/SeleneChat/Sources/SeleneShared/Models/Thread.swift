import Foundation

public struct Thread: Identifiable, Hashable {
    public let id: Int64
    public let name: String
    public let why: String?
    public let summary: String?
    public let status: String
    public let noteCount: Int
    public let momentumScore: Double?
    public let lastActivityAt: Date?
    public let createdAt: Date
    public let threadDigest: String?
    public let emotionalCharge: String?

    public init(
        id: Int64,
        name: String,
        why: String? = nil,
        summary: String? = nil,
        status: String,
        noteCount: Int,
        momentumScore: Double? = nil,
        lastActivityAt: Date? = nil,
        createdAt: Date,
        threadDigest: String? = nil,
        emotionalCharge: String? = nil
    ) {
        self.id = id
        self.name = name
        self.why = why
        self.summary = summary
        self.status = status
        self.noteCount = noteCount
        self.momentumScore = momentumScore
        self.lastActivityAt = lastActivityAt
        self.createdAt = createdAt
        self.threadDigest = threadDigest
        self.emotionalCharge = emotionalCharge
    }

    public var momentumDisplay: String {
        guard let score = momentumScore else { return "\u{2014}" }
        return String(format: "%.1f", score)
    }

    public var lastActivityDisplay: String {
        guard let date = lastActivityAt else { return "No activity" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    public var statusEmoji: String {
        switch status {
        case "active": return "\u{1F525}"
        case "paused": return "\u{23F8}\u{FE0F}"
        case "completed": return "\u{2705}"
        case "abandoned": return "\u{1F4A4}"
        default: return "\u{1F4CC}"
        }
    }
}

#if DEBUG
extension Thread {
    public static func mock(
        id: Int64 = 1,
        name: String = "Test Thread",
        why: String? = nil,
        summary: String? = "Test summary",
        status: String = "active",
        noteCount: Int = 5,
        momentumScore: Double? = 0.5,
        lastActivityAt: Date? = Date(),
        createdAt: Date = Date(),
        threadDigest: String? = nil,
        emotionalCharge: String? = nil
    ) -> Thread {
        Thread(
            id: id,
            name: name,
            why: why,
            summary: summary,
            status: status,
            noteCount: noteCount,
            momentumScore: momentumScore,
            lastActivityAt: lastActivityAt,
            createdAt: createdAt,
            threadDigest: threadDigest,
            emotionalCharge: emotionalCharge
        )
    }
}
#endif
