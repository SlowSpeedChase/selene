// ThingsTaskStatus.swift
// SeleneShared
//
// Phase 7.2e: Bidirectional Things Flow
// Model for task status returned from Things 3 via AppleScript

import Foundation

public struct ThingsTaskStatus: Codable {
    public let id: String
    public let status: String        // "open", "completed", "canceled"
    public let name: String
    public let completionDate: Date?
    public let modificationDate: Date
    public let creationDate: Date
    public let project: String?
    public let area: String?
    public let tags: [String]

    public var isCompleted: Bool {
        status == "completed"
    }

    public var isOpen: Bool {
        status == "open"
    }

    public var isCanceled: Bool {
        status == "canceled"
    }

    enum CodingKeys: String, CodingKey {
        case id, status, name, project, area, tags
        case completionDate = "completion_date"
        case modificationDate = "modification_date"
        case creationDate = "creation_date"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        status = try container.decode(String.self, forKey: .status)
        name = try container.decode(String.self, forKey: .name)
        project = try container.decodeIfPresent(String.self, forKey: .project)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        if let dateStr = try container.decodeIfPresent(String.self, forKey: .completionDate) {
            completionDate = dateFormatter.date(from: dateStr)
        } else {
            completionDate = nil
        }

        let modStr = try container.decode(String.self, forKey: .modificationDate)
        modificationDate = dateFormatter.date(from: modStr) ?? Date()

        let createStr = try container.decode(String.self, forKey: .creationDate)
        creationDate = dateFormatter.date(from: createStr) ?? Date()
    }

    // For creating test instances
    public init(
        id: String,
        status: String,
        name: String,
        completionDate: Date? = nil,
        modificationDate: Date = Date(),
        creationDate: Date = Date(),
        project: String? = nil,
        area: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.status = status
        self.name = name
        self.completionDate = completionDate
        self.modificationDate = modificationDate
        self.creationDate = creationDate
        self.project = project
        self.area = area
        self.tags = tags
    }
}

// MARK: - Sync Result

public struct SyncResult {
    public let total: Int
    public let synced: Int
    public let newlyCompleted: Int
    public let errors: Int

    public init(total: Int, synced: Int, newlyCompleted: Int, errors: Int) {
        self.total = total
        self.synced = synced
        self.newlyCompleted = newlyCompleted
        self.errors = errors
    }

    public var hasErrors: Bool { errors > 0 }
    public var allSynced: Bool { synced == total }
}

// MARK: - Things Status Errors

public enum ThingsStatusError: Error, LocalizedError {
    case scriptNotFound
    case executionFailed(String)
    case invalidResponse
    case taskNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "get-task-status.scpt not found"
        case .executionFailed(let msg):
            return "AppleScript failed: \(msg)"
        case .invalidResponse:
            return "Invalid JSON response from Things"
        case .taskNotFound(let taskId):
            return "Task not found: \(taskId)"
        }
    }
}
