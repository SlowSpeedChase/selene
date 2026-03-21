import Foundation

/// Summary of a task's lifecycle for contextual retrieval
public struct TaskOutcome: Hashable {
    public let taskTitle: String
    public let taskType: String?
    public let energyRequired: String?
    public let estimatedMinutes: Int?
    public let status: String              // "completed", "abandoned", or "open"
    public let createdAt: Date
    public let completedAt: Date?
    public let daysOpen: Int

    public init(taskTitle: String, taskType: String?, energyRequired: String?,
                estimatedMinutes: Int?, status: String, createdAt: Date,
                completedAt: Date?, daysOpen: Int) {
        self.taskTitle = taskTitle
        self.taskType = taskType
        self.energyRequired = energyRequired
        self.estimatedMinutes = estimatedMinutes
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.daysOpen = daysOpen
    }
}
