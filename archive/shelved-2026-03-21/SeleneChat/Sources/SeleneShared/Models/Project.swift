import Foundation

public struct Project: Identifiable, Hashable, Codable {
    public let id: Int
    public var name: String
    public var status: Status
    public var primaryConcept: String?
    public var thingsProjectId: String?
    public let createdAt: Date
    public var lastActiveAt: Date?
    public var completedAt: Date?
    public var testRun: String?
    public var isSystem: Bool = false

    // Computed from joins
    public var noteCount: Int = 0
    public var taskCount: Int = 0
    public var completedTaskCount: Int = 0
    public var threadCount: Int = 0
    public var hasReviewBadge: Bool = false

    public init(
        id: Int,
        name: String,
        status: Status,
        primaryConcept: String? = nil,
        thingsProjectId: String? = nil,
        createdAt: Date,
        lastActiveAt: Date? = nil,
        completedAt: Date? = nil,
        testRun: String? = nil,
        isSystem: Bool = false,
        noteCount: Int = 0,
        taskCount: Int = 0,
        completedTaskCount: Int = 0,
        threadCount: Int = 0,
        hasReviewBadge: Bool = false
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.primaryConcept = primaryConcept
        self.thingsProjectId = thingsProjectId
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.completedAt = completedAt
        self.testRun = testRun
        self.isSystem = isSystem
        self.noteCount = noteCount
        self.taskCount = taskCount
        self.completedTaskCount = completedTaskCount
        self.threadCount = threadCount
        self.hasReviewBadge = hasReviewBadge
    }

    public enum Status: String, CaseIterable, Codable {
        case active
        case parked
        case completed

        public var icon: String {
            switch self {
            case .active: return "flame"
            case .parked: return "parkingsign"
            case .completed: return "checkmark.circle"
            }
        }

        public var color: String {
            switch self {
            case .active: return "orange"
            case .parked: return "gray"
            case .completed: return "green"
            }
        }
    }

    public var timeSinceActive: String? {
        guard let lastActive = lastActiveAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastActive, relativeTo: Date())
    }
}
