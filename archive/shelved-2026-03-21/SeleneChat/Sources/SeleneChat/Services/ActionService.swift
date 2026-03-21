import SeleneShared
// ActionService.swift
// SeleneChat
//
// Phase 4: Thread Deep-Dive
// Service for capturing and managing actions extracted from deep-dive conversations

import Foundation

// MARK: - ThingsTask

/// Represents a task to be created in Things 3
struct ThingsTask {
    let title: String
    let notes: String
    let deadline: Date?
    let tags: [String]
    let listName: String?
}

// MARK: - CapturedAction

/// An action captured from a deep-dive conversation
struct CapturedAction {
    let action: ActionExtractor.ExtractedAction
    let threadName: String
    let capturedAt: Date
}

// MARK: - ActionService

/// Actor for capturing and managing actions extracted from deep-dive conversations
actor ActionService {

    // MARK: - Private Properties

    private var capturedActions: [CapturedAction] = []
    private let thingsService: ThingsURLService

    // MARK: - Initialization

    init(thingsService: ThingsURLService = .shared) {
        self.thingsService = thingsService
    }

    // MARK: - Public Methods

    /// Capture an action from a deep-dive conversation
    /// - Parameters:
    ///   - action: The extracted action to capture
    ///   - threadName: The name of the thread the action was extracted from
    func capture(_ action: ActionExtractor.ExtractedAction, threadName: String) {
        let captured = CapturedAction(
            action: action,
            threadName: threadName,
            capturedAt: Date()
        )
        capturedActions.append(captured)
    }

    /// Get all captured actions
    /// - Returns: Array of captured actions
    func getCapturedActions() -> [CapturedAction] {
        capturedActions
    }

    /// Clear all captured actions
    func clearActions() {
        capturedActions.removeAll()
    }

    /// Build a ThingsTask from an extracted action
    /// - Parameters:
    ///   - action: The extracted action
    ///   - threadName: The name of the thread
    /// - Returns: A ThingsTask ready to be sent to Things 3
    nonisolated func buildThingsTask(
        from action: ActionExtractor.ExtractedAction,
        threadName: String
    ) -> ThingsTask {
        let notes = "From Selene thread: \(threadName)\nEnergy: \(action.energy.rawValue)"

        let deadline: Date?
        switch action.timeframe {
        case .today:
            deadline = Date()
        case .thisWeek:
            deadline = Calendar.current.date(byAdding: .day, value: 7, to: Date())
        case .someday:
            deadline = nil
        }

        return ThingsTask(
            title: action.description,
            notes: notes,
            deadline: deadline,
            tags: ["selene", "deep-dive"],
            listName: nil
        )
    }

    /// Send an action to Things 3
    /// - Parameters:
    ///   - action: The extracted action to send
    ///   - threadName: The name of the thread
    func sendToThings(_ action: ActionExtractor.ExtractedAction, threadName: String) async {
        let task = buildThingsTask(from: action, threadName: threadName)

        // Use the existing ThingsURLService to create the task
        do {
            try await thingsService.createTask(
                title: task.title,
                notes: task.notes,
                tags: task.tags,
                energy: action.energy.rawValue
            )
        } catch {
            print("[ActionService] Failed to send task to Things: \(error)")
        }
    }

    /// Create a task in Things and link it to a thread in the database.
    /// - Parameters:
    ///   - action: The extracted action to create
    ///   - threadName: The name of the thread (used in task notes)
    ///   - threadId: The thread ID for database linking
    /// - Returns: The Things task ID
    @discardableResult
    func sendToThingsAndLinkThread(
        _ action: ActionExtractor.ExtractedAction,
        threadName: String,
        threadId: Int64
    ) async throws -> String {
        let task = buildThingsTask(from: action, threadName: threadName)

        let thingsTaskId = try await thingsService.createTask(
            title: task.title,
            notes: task.notes,
            tags: task.tags,
            energy: action.energy.rawValue
        )

        try await DatabaseService.shared.linkTaskToThread(
            threadId: threadId,
            thingsTaskId: thingsTaskId
        )

        return thingsTaskId
    }
}
