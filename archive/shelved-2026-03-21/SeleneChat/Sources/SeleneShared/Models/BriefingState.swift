import Foundation

/// Types of briefing cards
public enum BriefingCardType: Equatable {
    case whatChanged
    case needsAttention
    case connection
}

/// A single briefing card with data for one insight
public struct BriefingCard: Identifiable, Equatable {
    public let id = UUID()
    public let cardType: BriefingCardType

    // What Changed fields
    public var noteTitle: String?
    public var noteId: Int?
    public var threadName: String?
    public var threadId: Int64?
    public var date: Date?
    public var primaryTheme: String?
    public var energyLevel: String?

    // Needs Attention fields
    public var reason: String?
    public var noteCount: Int?
    public var openTaskCount: Int?

    // Connection fields
    public var noteATitle: String?
    public var noteAId: Int?
    public var threadAName: String?
    public var noteBTitle: String?
    public var noteBId: Int?
    public var threadBName: String?
    public var explanation: String?

    // Preview content (loaded on expand)
    public var notePreview: String?
    public var threadSummary: String?
    public var threadWhy: String?

    public var energyEmoji: String {
        switch energyLevel?.lowercased() {
        case "high": return "\u{26A1}"
        case "medium": return "\u{1F50B}"
        case "low": return "\u{1FAAB}"
        default: return ""
        }
    }

    // MARK: - Factory Methods

    public static func whatChanged(
        noteTitle: String,
        noteId: Int,
        threadName: String?,
        threadId: Int64?,
        date: Date,
        primaryTheme: String?,
        energyLevel: String?
    ) -> BriefingCard {
        BriefingCard(
            cardType: .whatChanged,
            noteTitle: noteTitle,
            noteId: noteId,
            threadName: threadName,
            threadId: threadId,
            date: date,
            primaryTheme: primaryTheme,
            energyLevel: energyLevel
        )
    }

    public static func needsAttention(
        threadName: String,
        threadId: Int64,
        reason: String,
        noteCount: Int,
        openTaskCount: Int
    ) -> BriefingCard {
        BriefingCard(
            cardType: .needsAttention,
            threadName: threadName,
            threadId: threadId,
            reason: reason,
            noteCount: noteCount,
            openTaskCount: openTaskCount
        )
    }

    public static func connection(
        noteATitle: String,
        noteAId: Int,
        threadAName: String,
        noteBTitle: String,
        noteBId: Int,
        threadBName: String,
        explanation: String
    ) -> BriefingCard {
        BriefingCard(
            cardType: .connection,
            noteATitle: noteATitle,
            noteAId: noteAId,
            threadAName: threadAName,
            noteBTitle: noteBTitle,
            noteBId: noteBId,
            threadBName: threadBName,
            explanation: explanation
        )
    }

    // Equatable (ignore UUID id)
    public static func == (lhs: BriefingCard, rhs: BriefingCard) -> Bool {
        lhs.cardType == rhs.cardType &&
        lhs.noteTitle == rhs.noteTitle &&
        lhs.noteId == rhs.noteId &&
        lhs.threadName == rhs.threadName
    }
}

/// Structured briefing with sections
public struct StructuredBriefing: Equatable {
    public let intro: String
    public let whatChanged: [BriefingCard]
    public let needsAttention: [BriefingCard]
    public let connections: [BriefingCard]
    public let generatedAt: Date

    public init(intro: String, whatChanged: [BriefingCard], needsAttention: [BriefingCard], connections: [BriefingCard], generatedAt: Date) {
        self.intro = intro
        self.whatChanged = whatChanged
        self.needsAttention = needsAttention
        self.connections = connections
        self.generatedAt = generatedAt
    }

    public var isEmpty: Bool {
        whatChanged.isEmpty && needsAttention.isEmpty && connections.isEmpty
    }
}

/// Loading status for the morning briefing
public enum BriefingStatus: Equatable {
    case notLoaded
    case loading
    case loaded(StructuredBriefing)
    case failed(String)
}

/// State container for the morning briefing feature
public struct BriefingState {
    public var status: BriefingStatus = .notLoaded

    public init(status: BriefingStatus = .notLoaded) {
        self.status = status
    }
}
