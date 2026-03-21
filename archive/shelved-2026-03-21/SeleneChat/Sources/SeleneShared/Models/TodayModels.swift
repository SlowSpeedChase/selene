import Foundation

/// A note with optional thread connection for Today view
public struct NoteWithThread: Identifiable {
    public let id: Int64
    public let title: String
    public let preview: String
    public let createdAt: Date
    public let threadName: String?
    public let threadId: Int64?

    public init(
        id: Int64,
        title: String,
        preview: String,
        createdAt: Date,
        threadName: String? = nil,
        threadId: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.createdAt = createdAt
        self.threadName = threadName
        self.threadId = threadId
    }

    public var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

/// Thread summary for Heating Up column
public struct ThreadSummary: Identifiable {
    public let id: Int64
    public let name: String
    public let summary: String
    public let noteCount: Int
    public let momentumScore: Double
    public let recentNoteTitles: [String]

    public init(
        id: Int64,
        name: String,
        summary: String,
        noteCount: Int,
        momentumScore: Double,
        recentNoteTitles: [String]
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.noteCount = noteCount
        self.momentumScore = momentumScore
        self.recentNoteTitles = recentNoteTitles
    }

    public var summaryPreview: String {
        String(summary.prefix(100))
    }
}
