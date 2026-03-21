import SeleneShared
// ThingsStatusService.swift
// SeleneChat
//
// Phase 7.2e: Bidirectional Things Flow
// Service for querying task status from Things 3 via AppleScript

import Foundation

class ThingsStatusService: ObservableObject {
    static let shared = ThingsStatusService()

    private let scriptPath: String

    init() {
        // Find script relative to project root
        let paths = [
            // Development: project root (relative to selene)
            "/Users/chaseeasterling/selene/scripts/things-bridge/get-task-status.scpt",
            // Worktree path
            "/Users/chaseeasterling/selene/.worktrees/bidirectional-things/scripts/things-bridge/get-task-status.scpt",
        ]

        self.scriptPath = paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]

        #if DEBUG
        print("[ThingsStatusService] Using script at: \(scriptPath)")
        #endif
    }

    /// Query Things for a single task's status
    func getTaskStatus(thingsId: String) async throws -> ThingsTaskStatus {
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw ThingsStatusError.scriptNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptPath, thingsId]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ThingsStatusError.executionFailed(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let jsonString = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ThingsStatusError.invalidResponse
        }

        #if DEBUG
        print("[ThingsStatusService] Response for \(thingsId): \(jsonString.prefix(100))...")
        #endif

        // Check for error response from AppleScript
        if jsonString.contains("\"error\"") {
            if jsonString.contains("not found") || jsonString.contains("Can't get to do id") {
                throw ThingsStatusError.taskNotFound(thingsId)
            }
            throw ThingsStatusError.executionFailed(jsonString)
        }

        // Parse JSON
        guard let jsonData = jsonString.data(using: .utf8) else {
            throw ThingsStatusError.invalidResponse
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ThingsTaskStatus.self, from: jsonData)
    }

    /// Batch sync all tracked tasks
    /// - Parameters:
    ///   - taskIds: Array of Things task IDs to sync
    ///   - updateHandler: Async closure called for each successfully synced task
    /// - Returns: Summary of sync results
    func syncAllTaskStatuses(
        taskIds: [String],
        updateHandler: @escaping (String, ThingsTaskStatus) async throws -> Void
    ) async -> SyncResult {
        var total = 0
        var synced = 0
        var newlyCompleted = 0
        var errors = 0

        for thingsId in taskIds {
            total += 1

            do {
                let status = try await getTaskStatus(thingsId: thingsId)
                try await updateHandler(thingsId, status)
                synced += 1

                if status.isCompleted {
                    newlyCompleted += 1
                }

                #if DEBUG
                print("[ThingsStatusService] Synced \(thingsId): \(status.status)")
                #endif

            } catch ThingsStatusError.taskNotFound {
                // Task deleted in Things - not counted as error, just skip
                #if DEBUG
                print("[ThingsStatusService] Task \(thingsId) not found in Things (may be deleted)")
                #endif
            } catch {
                errors += 1
                #if DEBUG
                print("[ThingsStatusService] Failed to sync task \(thingsId): \(error)")
                #endif
            }
        }

        #if DEBUG
        print("[ThingsStatusService] Sync complete: \(synced)/\(total) synced, \(newlyCompleted) completed, \(errors) errors")
        #endif

        return SyncResult(
            total: total,
            synced: synced,
            newlyCompleted: newlyCompleted,
            errors: errors
        )
    }

    /// Check if Things is available and the script exists
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: scriptPath)
    }
}
