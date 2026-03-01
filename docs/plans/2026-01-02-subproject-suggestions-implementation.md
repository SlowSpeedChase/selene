# Sub-Project Suggestions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Surface suggestions to split large project headings into their own sub-projects when 5+ tasks share a distinct concept.

**Architecture:** Detection runs on PlanningView load, finds task clusters by concept within existing Things projects. Suggestions surface in a new PlanningView section. User approves → create Things project + move tasks. User declines → suppress future suggestions for that heading.

**Tech Stack:** Swift/SwiftUI, SQLite.swift, AppleScript (existing create-project.scpt, assign-to-project.scpt)

---

## Overview

Phase 7.2f adds a suggestion system to PlanningView. When a Things project has 5+ tasks sharing a sub-concept distinct from the project's primary concept, Selene surfaces a card asking: "Spin off 'Frontend Work' as its own project?"

### Data Flow

```
PlanningView opens
    ↓
SubprojectSuggestionService.detectCandidates()
    ↓
Query task_metadata grouped by things_project_id + related_concepts
    ↓
Filter: 5+ tasks, concept != project's primary_concept
    ↓
Check: Not already dismissed in subproject_suggestions
    ↓
Surface in "Suggestions" section of PlanningView
    ↓
User approves → create-project.scpt + assign-to-project.scpt
User declines → INSERT dismissed INTO subproject_suggestions
```

---

## Task 1: Database Migration - subproject_suggestions table

**Files:**
- Create: `SeleneChat/Sources/Services/Migrations/Migration004_SubprojectSuggestions.swift`

**Step 1: Write the migration file**

```swift
// SeleneChat/Sources/Services/Migrations/Migration004_SubprojectSuggestions.swift
import Foundation
import SQLite

struct Migration004_SubprojectSuggestions {
    static func run(db: Connection) throws {
        // Create subproject_suggestions table
        try db.run("""
            CREATE TABLE IF NOT EXISTS subproject_suggestions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,

                -- Source project
                source_project_id TEXT NOT NULL,  -- things_project_id

                -- Suggested sub-project concept
                suggested_concept TEXT NOT NULL,
                suggested_name TEXT,  -- AI-generated or null

                -- Tasks that would move
                task_count INTEGER NOT NULL,
                task_ids TEXT NOT NULL,  -- JSON array of things_task_ids

                -- Status
                status TEXT NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending', 'approved', 'dismissed')),

                -- Result (if approved)
                created_project_id TEXT,  -- things_project_id of new project

                -- Timestamps
                detected_at TEXT DEFAULT CURRENT_TIMESTAMP,
                actioned_at TEXT,

                -- Prevent duplicate suggestions
                UNIQUE(source_project_id, suggested_concept)
            )
        """)

        // Index for quick lookups
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_subproject_suggestions_status
            ON subproject_suggestions(status)
        """)

        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_subproject_suggestions_source
            ON subproject_suggestions(source_project_id)
        """)
    }
}
```

**Step 2: Register migration in DatabaseService**

Edit `SeleneChat/Sources/Services/DatabaseService.swift:100` to add:

```swift
try? Migration004_SubprojectSuggestions.run(db: db!)
```

**Step 3: Verify migration runs**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

Expected: Build succeeds

**Step 4: Commit**

```bash
git add SeleneChat/Sources/Services/Migrations/Migration004_SubprojectSuggestions.swift
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(db): add migration 004 for subproject_suggestions table"
```

---

## Task 2: SubprojectSuggestion Model

**Files:**
- Create: `SeleneChat/Sources/Models/SubprojectSuggestion.swift`

**Step 1: Write the model**

```swift
// SeleneChat/Sources/Models/SubprojectSuggestion.swift
import Foundation

struct SubprojectSuggestion: Identifiable {
    let id: Int
    let sourceProjectId: String       // things_project_id
    let suggestedConcept: String
    var suggestedName: String?
    let taskCount: Int
    let taskIds: [String]             // things_task_ids
    var status: Status
    var createdProjectId: String?
    let detectedAt: Date
    var actionedAt: Date?

    // For display: loaded separately
    var sourceProjectName: String?

    enum Status: String {
        case pending
        case approved
        case dismissed
    }

    /// Human-readable suggestion text
    var suggestionText: String {
        let name = suggestedName ?? suggestedConcept.capitalized
        return "Spin off '\(name)' as its own project?"
    }

    /// Detail text showing task count
    var detailText: String {
        "\(taskCount) tasks share the '\(suggestedConcept)' concept"
    }
}
```

**Step 2: Verify build**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Models/SubprojectSuggestion.swift
git commit -m "feat(model): add SubprojectSuggestion for 7.2f"
```

---

## Task 3: SubprojectSuggestionService - Detection Logic

**Files:**
- Create: `SeleneChat/Sources/Services/SubprojectSuggestionService.swift`

**Step 1: Write the service**

```swift
// SeleneChat/Sources/Services/SubprojectSuggestionService.swift
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
        guard let db = db else { return [] }

        await MainActor.run { isDetecting = true }
        defer { Task { await MainActor.run { isDetecting = false } } }

        var candidates: [SubprojectSuggestion] = []

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
                    candidates.append(suggestion)
                }
            }
        }

        // Update published suggestions
        await MainActor.run { suggestions = candidates }

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
        guard let db = db else { throw ServiceError.notConfigured }

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
        guard let db = db else { throw ServiceError.notConfigured }

        try saveSuggestionAction(suggestion: suggestion, status: .dismissed, newProjectId: nil)

        // Refresh suggestions
        _ = try await detectCandidates()
    }

    private func createThingsProject(name: String) async throws -> String {
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene/scripts/things-bridge/create-project.scpt")
            .path

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

        if output.hasPrefix("ERROR:") {
            throw ServiceError.thingsError(output)
        }

        return output  // Returns things_project_id
    }

    private func assignTaskToProject(taskId: String, projectId: String) async throws {
        let scriptPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("selene/scripts/things-bridge/assign-to-project.scpt")
            .path

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
        case thingsError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "SubprojectSuggestionService not configured"
            case .thingsError(let message):
                return "Things error: \(message)"
            }
        }
    }
}
```

**Step 2: Verify build**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/SubprojectSuggestionService.swift
git commit -m "feat(service): add SubprojectSuggestionService for 7.2f detection"
```

---

## Task 4: SubprojectSuggestionCard View

**Files:**
- Create: `SeleneChat/Sources/Views/Planning/SubprojectSuggestionCard.swift`

**Step 1: Write the view**

```swift
// SeleneChat/Sources/Views/Planning/SubprojectSuggestionCard.swift
import SwiftUI

struct SubprojectSuggestionCard: View {
    let suggestion: SubprojectSuggestion
    let onApprove: () -> Void
    let onDismiss: () -> Void

    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Sub-Project Suggestion")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Suggestion text
            Text(suggestion.suggestionText)
                .font(.headline)

            // Detail text
            Text(suggestion.detailText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Source project (if available)
            if let sourceName = suggestion.sourceProjectName {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text("From: \(sourceName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    isProcessing = true
                    onApprove()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Create Project")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isProcessing)

                Button(action: {
                    onDismiss()
                }) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Not Now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
            }
            .padding(.top, 4)

            if isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Creating project...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

#Preview {
    SubprojectSuggestionCard(
        suggestion: SubprojectSuggestion(
            id: 1,
            sourceProjectId: "ABC123",
            suggestedConcept: "frontend",
            suggestedName: "Frontend Work",
            taskCount: 7,
            taskIds: ["t1", "t2", "t3", "t4", "t5", "t6", "t7"],
            status: .pending,
            createdProjectId: nil,
            detectedAt: Date(),
            actionedAt: nil,
            sourceProjectName: "Website Redesign"
        ),
        onApprove: { print("Approved") },
        onDismiss: { print("Dismissed") }
    )
    .padding()
    .frame(width: 400)
}
```

**Step 2: Verify build**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Views/Planning/SubprojectSuggestionCard.swift
git commit -m "feat(ui): add SubprojectSuggestionCard view"
```

---

## Task 5: Integrate Suggestions into PlanningView

**Files:**
- Modify: `SeleneChat/Sources/Views/PlanningView.swift`

**Step 1: Add service and state**

At the top of PlanningView struct, after existing @State vars:

```swift
// Phase 7.2f: Sub-project suggestions
@StateObject private var suggestionService = SubprojectSuggestionService.shared
@State private var isSuggestionsExpanded = true
```

**Step 2: Add suggestions section**

After `needsReviewSection` in the ScrollView VStack, add:

```swift
// Phase 7.2f: Sub-project suggestions
if !suggestionService.suggestions.isEmpty {
    suggestionsSection
        .id("suggestions")
}
```

**Step 3: Add sidebar button**

After the "Needs Review" sidebar button, add:

```swift
if !suggestionService.suggestions.isEmpty {
    sidebarButton(
        icon: "lightbulb.fill",
        label: "Suggestions",
        count: suggestionService.suggestions.count,
        color: .yellow,
        isExpanded: $isSuggestionsExpanded
    )
}
```

**Step 4: Add suggestionsSection computed property**

After `needsReviewSection`, add:

```swift
// MARK: - Phase 7.2f: Suggestions Section

private var suggestionsSection: some View {
    VStack(alignment: .leading, spacing: 0) {
        // Section header
        Button(action: { withAnimation { isSuggestionsExpanded.toggle() } }) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Suggestions")
                    .font(.headline)

                Text("(\(suggestionService.suggestions.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: isSuggestionsExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 8)

        if isSuggestionsExpanded {
            Divider()

            LazyVStack(spacing: 12) {
                ForEach(suggestionService.suggestions) { suggestion in
                    SubprojectSuggestionCard(
                        suggestion: suggestion,
                        onApprove: {
                            Task {
                                do {
                                    _ = try await suggestionService.approve(suggestion)
                                } catch {
                                    #if DEBUG
                                    print("[PlanningView] Approve error: \(error)")
                                    #endif
                                }
                            }
                        },
                        onDismiss: {
                            Task {
                                try? await suggestionService.dismiss(suggestion)
                            }
                        }
                    )
                }
            }
            .padding()
        }
    }
}
```

**Step 5: Add detection to syncThingsAndEvaluateTriggers**

In `syncThingsAndEvaluateTriggers()`, after the existing sync logic, add:

```swift
// Phase 7.2f: Detect sub-project candidates
suggestionService.configure(with: databaseService.db!)
_ = try? await suggestionService.detectCandidates()
```

**Step 6: Verify build**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

Expected: Build succeeds

**Step 7: Commit**

```bash
git add SeleneChat/Sources/Views/PlanningView.swift
git commit -m "feat(ui): integrate SubprojectSuggestions into PlanningView"
```

---

## Task 6: Configure Service in DatabaseService

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`

**Step 1: Configure SubprojectSuggestionService after migrations**

After the migration runs (around line 100), add:

```swift
// Configure services that need database access
SubprojectSuggestionService.shared.configure(with: db!)
```

**Step 2: Verify build**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(service): configure SubprojectSuggestionService on database connect"
```

---

## Task 7: Manual Testing

**Step 1: Build the app**

```bash
cd /Users/chaseeasterling/selene/.worktrees/sub-project-suggestions/SeleneChat
swift build
```

**Step 2: Run the app**

```bash
swift run
```

**Step 3: Test scenarios**

1. Open Planning tab
2. If you have 5+ tasks in a project with shared sub-concept, a suggestion card should appear
3. Click "Create Project" → should create project in Things and move tasks
4. Click "Not Now" → suggestion should disappear and not return

**Step 4: Document test results**

Update BRANCH-STATUS.md with test results.

---

## Task 8: Update Documentation

**Files:**
- Modify: `BRANCH-STATUS.md`
- Modify: `docs/plans/INDEX.md`

**Step 1: Update BRANCH-STATUS.md**

Mark planning as complete, move to testing stage.

**Step 2: Add to docs/plans/INDEX.md**

```markdown
| 2026-01-02-subproject-suggestions-implementation | Sub-Project Suggestions (7.2f) | In Progress | phase-7.2f/sub-project-suggestions |
```

**Step 3: Commit**

```bash
git add BRANCH-STATUS.md docs/plans/INDEX.md docs/plans/2026-01-02-subproject-suggestions-implementation.md
git commit -m "docs: add 7.2f implementation plan"
```

---

## Summary

**Files Created:**
- `SeleneChat/Sources/Services/Migrations/Migration004_SubprojectSuggestions.swift`
- `SeleneChat/Sources/Models/SubprojectSuggestion.swift`
- `SeleneChat/Sources/Services/SubprojectSuggestionService.swift`
- `SeleneChat/Sources/Views/Planning/SubprojectSuggestionCard.swift`
- `docs/plans/2026-01-02-subproject-suggestions-implementation.md`

**Files Modified:**
- `SeleneChat/Sources/Services/DatabaseService.swift` (migration + service config)
- `SeleneChat/Sources/Views/PlanningView.swift` (suggestions section)
- `BRANCH-STATUS.md`
- `docs/plans/INDEX.md`

**Testing:**
- Build succeeds after each task
- Manual testing with Things 3 app
- Approve/dismiss actions work correctly
