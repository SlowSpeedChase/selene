import Foundation

public struct InboxNote: Identifiable, Hashable, Codable {
    public let id: Int
    public let title: String
    public let content: String
    public let createdAt: Date

    // Inbox-specific
    public var inboxStatus: InboxStatus
    public var suggestedType: NoteType?
    public var suggestedProjectId: Int?
    public var suggestedProjectName: String?

    // From processed_notes
    public var concepts: [String]?
    public var primaryTheme: String?
    public var energyLevel: String?

    public enum InboxStatus: String, Codable {
        case pending
        case triaged
        case archived
    }

    public init(
        id: Int,
        title: String,
        content: String,
        createdAt: Date,
        inboxStatus: InboxStatus = .pending,
        suggestedType: NoteType? = nil,
        suggestedProjectId: Int? = nil,
        suggestedProjectName: String? = nil,
        concepts: [String]? = nil,
        primaryTheme: String? = nil,
        energyLevel: String? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.inboxStatus = inboxStatus
        self.suggestedType = suggestedType
        self.suggestedProjectId = suggestedProjectId
        self.suggestedProjectName = suggestedProjectName
        self.concepts = concepts
        self.primaryTheme = primaryTheme
        self.energyLevel = energyLevel
    }

    public var preview: String {
        String(content.prefix(150))
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
