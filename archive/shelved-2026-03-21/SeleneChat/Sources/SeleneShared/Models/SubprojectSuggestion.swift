import Foundation

public struct SubprojectSuggestion: Identifiable {
    public let id: Int
    public let sourceProjectId: String
    public let suggestedConcept: String
    public var suggestedName: String?
    public let taskCount: Int
    public let taskIds: [String]
    public var status: Status
    public var createdProjectId: String?
    public let detectedAt: Date
    public var actionedAt: Date?
    public var sourceProjectName: String?

    public init(
        id: Int,
        sourceProjectId: String,
        suggestedConcept: String,
        suggestedName: String? = nil,
        taskCount: Int,
        taskIds: [String],
        status: Status,
        createdProjectId: String? = nil,
        detectedAt: Date,
        actionedAt: Date? = nil,
        sourceProjectName: String? = nil
    ) {
        self.id = id
        self.sourceProjectId = sourceProjectId
        self.suggestedConcept = suggestedConcept
        self.suggestedName = suggestedName
        self.taskCount = taskCount
        self.taskIds = taskIds
        self.status = status
        self.createdProjectId = createdProjectId
        self.detectedAt = detectedAt
        self.actionedAt = actionedAt
        self.sourceProjectName = sourceProjectName
    }

    public enum Status: String {
        case pending
        case approved
        case dismissed
    }

    public var suggestionText: String {
        let name = suggestedName ?? suggestedConcept.capitalized
        return "Spin off '\(name)' as its own project?"
    }

    public var detailText: String {
        "\(taskCount) tasks share the '\(suggestedConcept)' concept"
    }
}
