import SeleneShared
// SubprojectSuggestionService.swift
// SeleneChat
//
// Phase 7.2f: Sub-Project Suggestions
// Service for detecting when 5+ tasks in a project share a sub-concept distinct from the project's primary concept

import Foundation
import SQLite

class SubprojectSuggestionService: ObservableObject {
    static let shared = SubprojectSuggestionService()

    @Published var suggestions: [SubprojectSuggestion] = []
    @Published var isDetecting = false

    private var db: Connection?

    // Detection threshold
    private let minTaskCount = 5

    // Table references
    private let taskMetadata = Table("task_metadata")
    private let projectMetadata = Table("project_metadata")
    private let subprojectSuggestions = Table("subproject_suggestions")

    // Columns
    private let thingsTaskId = Expression<String>("things_task_id")
    private let thingsProjectId = Expression<String?>("things_project_id")
    private let relatedConcepts = Expression<String?>("related_concepts")
    private let primaryConcept = Expression<String>("primary_concept")

    func configure(with db: Connection) {
        self.db = db
    }

    // MARK: - Detection

    /// Detect sub-project candidates across all projects
    func detectCandidates() async throws -> [SubprojectSuggestion] {
        guard db != nil else {
            await MainActor.run { isDetecting = false }
            return []
        }

        await MainActor.run { isDetecting = true }

        // Build candidates array
        var candidatesBuilder: [SubprojectSuggestion] = []

        // 1. Get all projects with their primary concepts
        let projects = try getProjectsWithConcepts()

        for (projectId, projectPrimaryConcept) in projects {
            // 2. Get tasks in this project with their concepts
            let taskConcepts = try getTaskConceptsInProject(projectId: projectId)

            // 3. Group by concept, filter to 5+, exclude primary
            let clusters = findConceptClusters(
                taskConcepts: taskConcepts,
                excludeConcept: projectPrimaryConcept
            )

            // 4. Check if already dismissed
            for cluster in clusters {
                if try !isSuggestionDismissed(projectId: projectId, concept: cluster.concept) {
                    let suggestion = SubprojectSuggestion(
                        id: 0,  // Will be set on insert
                        sourceProjectId: projectId,
                        suggestedConcept: cluster.concept,
                        suggestedName: nil,
                        taskCount: cluster.taskIds.count,
                        taskIds: cluster.taskIds,
                        status: .pending,
                        createdProjectId: nil,
                        detectedAt: Date(),
                        actionedAt: nil
                    )
                    candidatesBuilder.append(suggestion)
                }
            }
        }

        // Make immutable for safe capture
        let candidates = candidatesBuilder

        // Update published suggestions and reset detecting state
        await MainActor.run {
            suggestions = candidates
            isDetecting = false
        }

        return candidates
    }

    private func getProjectsWithConcepts() throws -> [(String, String)] {
        guard let db = db else { return [] }

        var results: [(String, String)] = []

        let query = projectMetadata.select(
            Expression<String>("things_project_id"),
            primaryConcept
        )

        for row in try db.prepare(query) {
            let projectId = row[Expression<String>("things_project_id")]
            let concept = row[primaryConcept]
            results.append((projectId, concept))
        }

        return results
    }

    private func getTaskConceptsInProject(projectId: String) throws -> [(taskId: String, concepts: [String])] {
        guard let db = db else { return [] }

        var results: [(taskId: String, concepts: [String])] = []

        let query = taskMetadata
            .select(thingsTaskId, relatedConcepts)
            .filter(thingsProjectId == projectId)

        for row in try db.prepare(query) {
            let taskId = row[thingsTaskId]
            let conceptsJson = row[relatedConcepts] ?? "[]"
            let concepts = (try? JSONDecoder().decode([String].self, from: conceptsJson.data(using: .utf8) ?? Data())) ?? []
            results.append((taskId: taskId, concepts: concepts))
        }

        return results
    }

    private struct ConceptCluster {
        let concept: String
        let taskIds: [String]
    }

    private func findConceptClusters(
        taskConcepts: [(taskId: String, concepts: [String])],
        excludeConcept: String
    ) -> [ConceptCluster] {
        // Group tasks by concept
        var conceptToTasks: [String: [String]] = [:]

        for (taskId, concepts) in taskConcepts {
            for concept in concepts {
                if concept.lowercased() != excludeConcept.lowercased() {
                    conceptToTasks[concept, default: []].append(taskId)
                }
            }
        }

        // Filter to 5+ tasks
        return conceptToTasks
            .filter { $0.value.count >= minTaskCount }
            .map { ConceptCluster(concept: $0.key, taskIds: $0.value) }
    }

    private func isSuggestionDismissed(projectId: String, concept: String) throws -> Bool {
        guard let db = db else { return false }

        let query = subprojectSuggestions
            .filter(Expression<String>("source_project_id") == projectId)
            .filter(Expression<String>("suggested_concept") == concept)
            .filter(Expression<String>("status") == "dismissed")

        return try db.pluck(query) != nil
    }

    // MARK: - Actions

    /// Approve a suggestion: create project in Things, move tasks
    func approve(_ suggestion: SubprojectSuggestion) async throws -> String {
        guard db != nil else { throw ServiceError.notConfigured }

        // 1. Generate project name (use concept for now, could call LLM)
        let projectName = suggestion.suggestedName ?? suggestion.suggestedConcept.capitalized

        // 2. Create project in Things via AppleScript
        let newProjectId = try await createThingsProject(name: projectName)

        // 3. Move tasks to new project
        for taskId in suggestion.taskIds {
            try await assignTaskToProject(taskId: taskId, projectId: newProjectId)
        }

        // 4. Update database
        try saveSuggestionAction(suggestion: suggestion, status: .approved, newProjectId: newProjectId)

        // 5. Refresh suggestions
        _ = try await detectCandidates()

        return newProjectId
    }

    /// Dismiss a suggestion: mark as dismissed, won't show again
    func dismiss(_ suggestion: SubprojectSuggestion) async throws {
        guard db != nil else { throw ServiceError.notConfigured }

        try saveSuggestionAction(suggestion: suggestion, status: .dismissed, newProjectId: nil)

        // Refresh suggestions
        _ = try await detectCandidates()
    }

    private func createThingsProject(name: String) async throws -> String {
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene/scripts/things-bridge/create-project.scpt")
            .path

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw ServiceError.scriptNotFound(scriptPath)
        }

        // Create temp JSON file for project data
        let tempDir = FileManager.default.temporaryDirectory
        let jsonPath = tempDir.appendingPathComponent("project-\(UUID().uuidString).json")

        let projectData = ["name": name]
        let jsonData = try JSONEncoder().encode(projectData)
        try jsonData.write(to: jsonPath)

        defer { try? FileManager.default.removeItem(at: jsonPath) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptPath, jsonPath.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        #if DEBUG
        print("[SubprojectSuggestionService] createThingsProject response: \(output.prefix(100))...")
        #endif

        if output.hasPrefix("ERROR:") {
            throw ServiceError.thingsError(output)
        }

        return output  // Returns things_project_id
    }

    private func assignTaskToProject(taskId: String, projectId: String) async throws {
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene/scripts/things-bridge/assign-to-project.scpt")
            .path

        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw ServiceError.scriptNotFound(scriptPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [scriptPath, taskId, projectId]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        #if DEBUG
        print("[SubprojectSuggestionService] assignTaskToProject \(taskId) -> \(projectId): \(output.prefix(50))...")
        #endif

        if output.hasPrefix("ERROR:") {
            throw ServiceError.thingsError(output)
        }
    }

    private func saveSuggestionAction(
        suggestion: SubprojectSuggestion,
        status: SubprojectSuggestion.Status,
        newProjectId: String?
    ) throws {
        guard let db = db else { throw ServiceError.notConfigured }

        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        let taskIdsJson = (try? JSONEncoder().encode(suggestion.taskIds))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        // Insert or update
        try db.run("""
            INSERT INTO subproject_suggestions
            (source_project_id, suggested_concept, task_count, task_ids, status, created_project_id, detected_at, actioned_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source_project_id, suggested_concept) DO UPDATE SET
                status = excluded.status,
                created_project_id = excluded.created_project_id,
                actioned_at = excluded.actioned_at
        """, suggestion.sourceProjectId, suggestion.suggestedConcept, suggestion.taskCount,
             taskIdsJson, status.rawValue, newProjectId, dateFormatter.string(from: suggestion.detectedAt), now)
    }

    // MARK: - Errors

    enum ServiceError: Error, LocalizedError {
        case notConfigured
        case scriptNotFound(String)
        case thingsError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "SubprojectSuggestionService not configured"
            case .scriptNotFound(let path):
                return "Script not found: \(path)"
            case .thingsError(let message):
                return "Things error: \(message)"
            }
        }
    }
}
