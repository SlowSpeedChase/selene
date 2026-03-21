import SeleneShared
import Foundation
import AppKit

class ThingsURLService {
    static let shared = ThingsURLService()

    private var authToken: String? {
        ProcessInfo.processInfo.environment["THINGS_AUTH_TOKEN"]
    }

    // Path to AppleScript for creating tasks
    private let addTaskScriptPath: String

    // Database service for recording task links
    private var databaseService: DatabaseService?

    private init() {
        // Find script relative to project root
        let paths = [
            "/Users/chaseeasterling/selene/scripts/things-bridge/add-task-to-things.scpt",
            "/Users/chaseeasterling/selene/.worktrees/bidirectional-things/scripts/things-bridge/add-task-to-things.scpt",
        ]
        self.addTaskScriptPath = paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]
    }

    func configure(with db: DatabaseService) {
        self.databaseService = db
    }

    enum ThingsError: Error, LocalizedError {
        case invalidURL
        case missingAuthToken
        case openFailed
        case scriptNotFound
        case scriptFailed(String)
        case databaseNotConfigured

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Failed to build Things URL"
            case .missingAuthToken:
                return "THINGS_AUTH_TOKEN environment variable not set"
            case .openFailed:
                return "Failed to open Things"
            case .scriptNotFound:
                return "add-task-to-things.scpt not found"
            case .scriptFailed(let msg):
                return "AppleScript failed: \(msg)"
            case .databaseNotConfigured:
                return "Database service not configured"
            }
        }
    }

    // MARK: - Public Methods

    /// Build URL for adding a task to Things
    func buildAddTaskURL(
        title: String,
        notes: String? = nil,
        tags: [String] = [],
        sourceNoteId: Int? = nil,
        threadId: Int? = nil,
        deadline: Date? = nil
    ) -> URL? {
        var components = URLComponents(string: "things:///add")
        var queryItems: [URLQueryItem] = []

        // Required: title
        queryItems.append(URLQueryItem(name: "title", value: title))

        // Optional: notes with selene metadata
        var notesContent = notes ?? ""
        if let noteId = sourceNoteId, let tid = threadId {
            if !notesContent.isEmpty {
                notesContent += "\n\n"
            }
            notesContent += "[selene:note-\(noteId):thread-\(tid)]"
        }
        if !notesContent.isEmpty {
            queryItems.append(URLQueryItem(name: "notes", value: notesContent))
        }

        // Tags - always include "selene" tag
        var allTags = tags
        if !allTags.contains("selene") {
            allTags.append("selene")
        }
        queryItems.append(URLQueryItem(name: "tags", value: allTags.joined(separator: ",")))

        // Deadline
        if let deadline = deadline {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            queryItems.append(URLQueryItem(name: "deadline", value: formatter.string(from: deadline)))
        }

        // Auth token for modifications
        if let token = authToken {
            queryItems.append(URLQueryItem(name: "auth-token", value: token))
        }

        // Don't show quick entry
        queryItems.append(URLQueryItem(name: "show-quick-entry", value: "false"))

        components?.queryItems = queryItems
        return components?.url
    }

    /// Create a task in Things using AppleScript and record in task_links
    /// Returns the Things task ID
    @discardableResult
    func createTask(
        title: String,
        notes: String? = nil,
        tags: [String] = [],
        energy: String? = nil,
        sourceNoteId: Int? = nil,
        threadId: Int? = nil,
        project: String? = nil,  // Things project name to assign to
        heading: String? = nil   // Things heading (sub-group within project)
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: addTaskScriptPath) else {
            throw ThingsError.scriptNotFound
        }

        // Build energy tag if provided
        var allTags = tags
        if let energy = energy {
            allTags.append("\(energy)-energy")
        }
        // Always include selene tag
        if !allTags.contains("selene") {
            allTags.append("selene")
        }

        // Build notes with selene metadata
        var notesContent = notes ?? ""
        if let noteId = sourceNoteId, let tid = threadId {
            if !notesContent.isEmpty {
                notesContent += "\n\n"
            }
            notesContent += "[selene:note-\(noteId):thread-\(tid)]"
        }

        // Create temporary JSON file for the AppleScript
        let tempDir = FileManager.default.temporaryDirectory
        let jsonFile = tempDir.appendingPathComponent("selene-task-\(UUID().uuidString).json")

        var taskData: [String: Any] = [
            "title": title,
            "notes": notesContent,
            "tags": allTags
        ]

        // Add project if specified
        if let project = project, !project.isEmpty {
            taskData["project"] = project
        }

        // Add heading if specified
        if let heading = heading, !heading.isEmpty {
            taskData["heading"] = heading
        }

        let jsonData = try JSONSerialization.data(withJSONObject: taskData)
        try jsonData.write(to: jsonFile)

        defer {
            try? FileManager.default.removeItem(at: jsonFile)
        }

        // Execute AppleScript
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [addTaskScriptPath, jsonFile.path]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Check for errors
        if output.hasPrefix("ERROR:") || process.terminationStatus != 0 {
            throw ThingsError.scriptFailed(output)
        }

        let thingsTaskId = output
        print("[ThingsURLService] Created task in Things: \(title) (ID: \(thingsTaskId))")

        // Record in task_links if we have a thread ID
        if let tid = threadId, let noteId = sourceNoteId {
            try await recordTaskLink(thingsTaskId: thingsTaskId, threadId: tid, noteId: noteId, heading: heading)
        }

        return thingsTaskId
    }

    /// Record a task link in the database
    private func recordTaskLink(thingsTaskId: String, threadId: Int, noteId: Int, heading: String? = nil) async throws {
        guard let db = databaseService else {
            print("[ThingsURLService] Warning: Database not configured, skipping task_links insert")
            return
        }

        try await db.insertTaskLink(thingsTaskId: thingsTaskId, threadId: threadId, noteId: noteId, heading: heading)
        print("[ThingsURLService] Recorded task link: \(thingsTaskId) -> thread \(threadId), heading: \(heading ?? "none")")
    }

    /// Open Things to show a specific item
    func showTask(thingsId: String) async throws {
        guard let url = URL(string: "things:///show?id=\(thingsId)") else {
            throw ThingsError.invalidURL
        }

        let success = await MainActor.run {
            NSWorkspace.shared.open(url)
        }

        if !success {
            throw ThingsError.openFailed
        }
    }

    /// Check if Things is installed
    func isThingsInstalled() -> Bool {
        let url = URL(string: "things:///")!
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    // MARK: - Task Status Sync

    /// Parsed response from get-task-status.scpt
    struct TaskStatusResult {
        let id: String
        let status: String  // "open", "completed", "canceled"
        let name: String
        let completionDate: String?  // "YYYY-MM-DD" or nil
    }

    /// Path to the get-task-status AppleScript
    private var getTaskStatusScriptPath: String {
        "/Users/chaseeasterling/selene/scripts/things-bridge/get-task-status.scpt"
    }

    /// Parse JSON response from get-task-status.scpt
    static func parseTaskStatusResponse(_ jsonString: String) -> TaskStatusResult? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Check for error response
        if json["error"] != nil {
            return nil
        }

        guard let id = json["id"] as? String,
              let status = json["status"] as? String,
              let name = json["name"] as? String else {
            return nil
        }

        let completionDate = json["completion_date"] as? String

        return TaskStatusResult(
            id: id,
            status: status,
            name: name,
            completionDate: completionDate
        )
    }

    /// Query Things for a single task's status via AppleScript
    func getTaskStatus(thingsTaskId: String) async throws -> TaskStatusResult? {
        guard FileManager.default.fileExists(atPath: getTaskStatusScriptPath) else {
            print("[ThingsURLService] get-task-status.scpt not found")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [getTaskStatusScriptPath, thingsTaskId]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0, !output.isEmpty else {
            return nil
        }

        return Self.parseTaskStatusResponse(output)
    }

    /// Sync task statuses for a list of incomplete tasks.
    /// Returns the Things IDs of tasks that were newly marked as completed.
    func syncTaskStatuses(for tasks: [ThreadTask], databaseService: DatabaseService) async -> [String] {
        var newlyCompleted: [String] = []

        for task in tasks where !task.isCompleted {
            do {
                guard let status = try await getTaskStatus(thingsTaskId: task.thingsTaskId) else {
                    continue
                }

                if status.status == "completed" || status.status == "canceled" {
                    let completionDate: Date
                    if let dateStr = status.completionDate {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd"
                        completionDate = formatter.date(from: dateStr) ?? Date()
                    } else {
                        completionDate = Date()
                    }

                    try await databaseService.markThreadTaskCompleted(
                        thingsTaskId: task.thingsTaskId,
                        completedAt: completionDate
                    )

                    try await databaseService.recordThreadActivity(
                        threadId: task.threadId,
                        type: "task_completed",
                        timestamp: completionDate
                    )

                    newlyCompleted.append(task.thingsTaskId)
                    print("[ThingsURLService] Task \(task.thingsTaskId) synced as completed")
                }
            } catch {
                print("[ThingsURLService] Failed to sync task \(task.thingsTaskId): \(error)")
            }
        }

        return newlyCompleted
    }
}
