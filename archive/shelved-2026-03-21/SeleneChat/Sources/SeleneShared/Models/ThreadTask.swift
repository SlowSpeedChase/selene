import Foundation

/// A task linked to a semantic thread
public struct ThreadTask: Identifiable, Hashable {
    public let id: Int64
    public let threadId: Int64
    public let thingsTaskId: String
    public let createdAt: Date
    public let completedAt: Date?

    /// Title fetched from Things (not stored in Selene)
    public var title: String?

    public init(
        id: Int64,
        threadId: Int64,
        thingsTaskId: String,
        createdAt: Date,
        completedAt: Date? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.threadId = threadId
        self.thingsTaskId = thingsTaskId
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.title = title
    }

    /// Whether the task is completed
    public var isCompleted: Bool {
        completedAt != nil
    }

    public var completedDisplay: String {
        guard let date = completedAt else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Done \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

#if DEBUG
extension ThreadTask {
    public static func mock(
        id: Int64 = 1,
        threadId: Int64 = 1,
        thingsTaskId: String = "ABC123",
        title: String? = "Sample Task",
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) -> ThreadTask {
        ThreadTask(
            id: id,
            threadId: threadId,
            thingsTaskId: thingsTaskId,
            createdAt: createdAt,
            completedAt: completedAt,
            title: title
        )
    }
}
#endif
