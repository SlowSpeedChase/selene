# Phase 7.2e: Bidirectional Things Flow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Enable SeleneChat to query task status from Things 3 and resurface planning threads based on progress triggers.

**Architecture:** ThingsStatusService calls existing AppleScript via Process, ResurfaceTriggerService evaluates YAML config against task completion data, PlanningView triggers sync on appear and updates thread status to "review" when triggers fire.

**Tech Stack:** Swift 5.9, SwiftUI, SQLite.swift, AppleScript (via Process), Yams (YAML parsing)

**Design Doc:** `docs/plans/2026-01-02-bidirectional-things-flow-design.md`

---

## Task 1: Database Migration - task_links Status Columns

**Files:**
- Create: `SeleneChat/Sources/Services/Migrations/Migration003_BidirectionalThings.swift`
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift` (add migration call)

**Step 1: Create migration file**

```swift
// SeleneChat/Sources/Services/Migrations/Migration003_BidirectionalThings.swift
import Foundation
import SQLite

struct Migration003_BidirectionalThings {
    static func migrate(_ db: Connection) throws {
        // Add status tracking columns to task_links
        try db.run("""
            ALTER TABLE task_links ADD COLUMN things_status TEXT DEFAULT 'open'
        """)

        try db.run("""
            ALTER TABLE task_links ADD COLUMN things_completed_at TEXT
        """)

        try db.run("""
            ALTER TABLE task_links ADD COLUMN last_synced_at TEXT
        """)

        // Add resurface columns to discussion_threads
        try db.run("""
            ALTER TABLE discussion_threads ADD COLUMN resurface_reason TEXT
        """)

        try db.run("""
            ALTER TABLE discussion_threads ADD COLUMN last_resurfaced_at TEXT
        """)

        print("[Migration003] Added bidirectional Things sync columns")
    }
}
```

**Step 2: Add migration to DatabaseService**

In `DatabaseService.swift`, find the `runMigrations()` method and add:

```swift
// After Migration002
try Migration003_BidirectionalThings.migrate(db)
```

**Step 3: Build to verify no syntax errors**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add SeleneChat/Sources/Services/Migrations/Migration003_BidirectionalThings.swift
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(db): add migration 003 for bidirectional Things sync"
```

---

## Task 2: Update DiscussionThread Model

**Files:**
- Modify: `SeleneChat/Sources/Models/DiscussionThread.swift`

**Step 1: Add new status case and fields**

Find the `ThreadStatus` enum and add `review` case:

```swift
enum ThreadStatus: String, Codable {
    case pending
    case active
    case review      // NEW: resurfaced for user attention
    case completed
    case dismissed

    var icon: String {
        switch self {
        case .pending: return "clock"
        case .active: return "play.circle"
        case .review: return "arrow.triangle.2.circlepath"  // NEW
        case .completed: return "checkmark.circle"
        case .dismissed: return "xmark.circle"
        }
    }
}
```

**Step 2: Add resurface fields to DiscussionThread struct**

```swift
struct DiscussionThread: Identifiable, Codable {
    // ... existing fields ...

    // Resurface tracking (NEW)
    var resurfaceReason: String?
    var lastResurfacedAt: Date?

    // Computed property for display message
    var resurfaceMessage: String? {
        guard let reason = resurfaceReason else { return nil }
        // Map reason codes to user-friendly messages
        if reason.starts(with: "progress_") {
            return "Good progress! Ready to plan next steps?"
        } else if reason.starts(with: "stuck_") {
            return "This seems stuck. Want to rethink the approach?"
        } else if reason == "completion" {
            return "All tasks done! Want to reflect or plan what's next?"
        }
        return nil
    }
}
```

**Step 3: Update Row initializer to read new columns**

In the `init(from row:)` initializer, add:

```swift
self.resurfaceReason = try? row.get(Expression<String?>("resurface_reason"))
if let resurfacedStr = try? row.get(Expression<String?>("last_resurfaced_at")) {
    self.lastResurfacedAt = ISO8601DateFormatter().date(from: resurfacedStr)
}
```

**Step 4: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Models/DiscussionThread.swift
git commit -m "feat(model): add review status and resurface fields to DiscussionThread"
```

---

## Task 3: Create ThingsTaskStatus Model

**Files:**
- Create: `SeleneChat/Sources/Models/ThingsTaskStatus.swift`

**Step 1: Create the model file**

```swift
// SeleneChat/Sources/Models/ThingsTaskStatus.swift
import Foundation

struct ThingsTaskStatus: Codable {
    let id: String
    let status: String        // "open", "completed", "canceled"
    let name: String
    let completionDate: Date?
    let modificationDate: Date
    let creationDate: Date
    let project: String?
    let area: String?
    let tags: [String]

    var isCompleted: Bool {
        status == "completed"
    }

    var isOpen: Bool {
        status == "open"
    }

    enum CodingKeys: String, CodingKey {
        case id, status, name, project, area, tags
        case completionDate = "completion_date"
        case modificationDate = "modification_date"
        case creationDate = "creation_date"
    }

    init(from decoder: Decoder) throws {
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
}

struct SyncResult {
    let total: Int
    let synced: Int
    let newlyCompleted: Int
    let errors: Int
}

enum ThingsStatusError: Error, LocalizedError {
    case scriptNotFound
    case executionFailed(String)
    case invalidResponse
    case taskNotFound(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "get-task-status.scpt not found"
        case .executionFailed(let msg):
            return "AppleScript failed: \(msg)"
        case .invalidResponse:
            return "Invalid JSON response from Things"
        case .taskNotFound(let id):
            return "Task not found: \(id)"
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Models/ThingsTaskStatus.swift
git commit -m "feat(model): add ThingsTaskStatus and SyncResult models"
```

---

## Task 4: Create ThingsStatusService

**Files:**
- Create: `SeleneChat/Sources/Services/ThingsStatusService.swift`

**Step 1: Create the service**

```swift
// SeleneChat/Sources/Services/ThingsStatusService.swift
import Foundation

class ThingsStatusService: ObservableObject {
    static let shared = ThingsStatusService()

    private let scriptPath: String

    init() {
        // Find script relative to app or project
        let paths = [
            // Development: project root
            "/Users/chaseeasterling/selene/scripts/things-bridge/get-task-status.scpt",
            // Could add app bundle path for distribution
        ]

        self.scriptPath = paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]
    }

    /// Query Things for a single task's status
    func getTaskStatus(thingsId: String) async throws -> ThingsTaskStatus {
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
        guard let jsonString = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw ThingsStatusError.invalidResponse
        }

        // Check for error response
        if jsonString.contains("\"error\"") {
            if jsonString.contains("not found") {
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
            } catch ThingsStatusError.taskNotFound {
                // Task deleted in Things - not an error, just skip
                print("Task \(thingsId) not found in Things (may be deleted)")
            } catch {
                errors += 1
                print("Failed to sync task \(thingsId): \(error)")
            }
        }

        return SyncResult(
            total: total,
            synced: synced,
            newlyCompleted: newlyCompleted,
            errors: errors
        )
    }
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/ThingsStatusService.swift
git commit -m "feat(service): add ThingsStatusService for AppleScript bridge"
```

---

## Task 5: Create ResurfaceConfig Model

**Files:**
- Create: `SeleneChat/Sources/Models/ResurfaceConfig.swift`

**Step 1: Create config model**

```swift
// SeleneChat/Sources/Models/ResurfaceConfig.swift
import Foundation

struct ResurfaceConfig: Codable {
    let progressTrigger: ProgressTrigger
    let stuckTrigger: StuckTrigger
    let completionTrigger: CompletionTrigger
    let deadlineTrigger: DeadlineTrigger
    let sync: SyncConfig

    struct ProgressTrigger: Codable {
        let enabled: Bool
        let thresholdPercent: Int
        let message: String
        let triggerOnce: Bool

        enum CodingKeys: String, CodingKey {
            case enabled
            case thresholdPercent = "threshold_percent"
            case message
            case triggerOnce = "trigger_once"
        }
    }

    struct StuckTrigger: Codable {
        let enabled: Bool
        let daysInactive: Int
        let message: String
        let triggerOnce: Bool
        let cooldownDays: Int

        enum CodingKeys: String, CodingKey {
            case enabled
            case daysInactive = "days_inactive"
            case message
            case triggerOnce = "trigger_once"
            case cooldownDays = "cooldown_days"
        }
    }

    struct CompletionTrigger: Codable {
        let enabled: Bool
        let thresholdPercent: Int
        let message: String
        let celebration: Bool

        enum CodingKeys: String, CodingKey {
            case enabled
            case thresholdPercent = "threshold_percent"
            case message
            case celebration
        }
    }

    struct DeadlineTrigger: Codable {
        let enabled: Bool
        let daysBefore: Int
        let message: String
        let requireIncomplete: Bool

        enum CodingKeys: String, CodingKey {
            case enabled
            case daysBefore = "days_before"
            case message
            case requireIncomplete = "require_incomplete"
        }
    }

    struct SyncConfig: Codable {
        let intervalMinutes: Int
        let onLaunch: Bool
        let onTabOpen: Bool

        enum CodingKeys: String, CodingKey {
            case intervalMinutes = "interval_minutes"
            case onLaunch = "on_launch"
            case onTabOpen = "on_tab_open"
        }
    }

    enum CodingKeys: String, CodingKey {
        case progressTrigger = "progress_trigger"
        case stuckTrigger = "stuck_trigger"
        case completionTrigger = "completion_trigger"
        case deadlineTrigger = "deadline_trigger"
        case sync
    }
}

enum ResurfaceTrigger {
    case progress(percent: Int, message: String)
    case stuck(days: Int, message: String)
    case completion(message: String)
    case deadline(daysUntil: Int, message: String)

    var reasonCode: String {
        switch self {
        case .progress(let percent, _): return "progress_\(percent)"
        case .stuck(let days, _): return "stuck_\(days)d"
        case .completion: return "completion"
        case .deadline(let days, _): return "deadline_\(days)d"
        }
    }

    var message: String {
        switch self {
        case .progress(_, let msg), .stuck(_, let msg),
             .completion(let msg), .deadline(_, let msg):
            return msg
        }
    }
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Models/ResurfaceConfig.swift
git commit -m "feat(model): add ResurfaceConfig and ResurfaceTrigger models"
```

---

## Task 6: Add Yams Dependency for YAML Parsing

**Files:**
- Modify: `SeleneChat/Package.swift`

**Step 1: Add Yams dependency**

In `Package.swift`, add to dependencies array:

```swift
.package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
```

And add to target dependencies:

```swift
.product(name: "Yams", package: "Yams"),
```

**Step 2: Resolve dependencies**

Run: `cd SeleneChat && swift package resolve`
Expected: `Fetching https://github.com/jpsim/Yams.git` then success

**Step 3: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 4: Commit**

```bash
git add SeleneChat/Package.swift
git commit -m "chore(deps): add Yams for YAML config parsing"
```

---

## Task 7: Create ResurfaceTriggerService

**Files:**
- Create: `SeleneChat/Sources/Services/ResurfaceTriggerService.swift`

**Step 1: Create the service**

```swift
// SeleneChat/Sources/Services/ResurfaceTriggerService.swift
import Foundation
import Yams

class ResurfaceTriggerService: ObservableObject {
    static let shared = ResurfaceTriggerService()

    private let config: ResurfaceConfig

    init() {
        self.config = Self.loadConfig()
    }

    private static func loadConfig() -> ResurfaceConfig {
        let configPaths = [
            "/Users/chaseeasterling/selene/config/resurface-triggers.yaml",
            // Fallback paths if needed
        ]

        for path in configPaths {
            if let data = FileManager.default.contents(atPath: path),
               let yamlString = String(data: data, encoding: .utf8) {
                do {
                    let decoder = YAMLDecoder()
                    return try decoder.decode(ResurfaceConfig.self, from: yamlString)
                } catch {
                    print("Failed to parse config at \(path): \(error)")
                }
            }
        }

        // Return default config if file not found
        return defaultConfig()
    }

    private static func defaultConfig() -> ResurfaceConfig {
        ResurfaceConfig(
            progressTrigger: .init(enabled: true, thresholdPercent: 50, message: "Good progress! Ready to plan next steps?", triggerOnce: true),
            stuckTrigger: .init(enabled: true, daysInactive: 3, message: "This seems stuck. Want to rethink the approach?", triggerOnce: false, cooldownDays: 7),
            completionTrigger: .init(enabled: true, thresholdPercent: 100, message: "All tasks done! Want to reflect or plan what's next?", celebration: true),
            deadlineTrigger: .init(enabled: true, daysBefore: 2, message: "Deadline approaching! Review your tasks?", requireIncomplete: true),
            sync: .init(intervalMinutes: 0, onLaunch: false, onTabOpen: true)
        )
    }

    /// Evaluate all triggers for a thread based on its tasks
    func evaluateTriggers(
        thread: DiscussionThread,
        tasks: [ThingsTaskStatus]
    ) -> ResurfaceTrigger? {
        guard !tasks.isEmpty else { return nil }

        let total = tasks.count
        let completed = tasks.filter { $0.isCompleted }.count
        let percent = (completed * 100) / total

        // Priority order: completion > progress > stuck

        // 1. Completion trigger (100%)
        if config.completionTrigger.enabled && percent == 100 {
            return .completion(message: config.completionTrigger.message)
        }

        // 2. Progress trigger (threshold %)
        if config.progressTrigger.enabled && percent >= config.progressTrigger.thresholdPercent && percent < 100 {
            // Check trigger_once - only fire if not already resurfaced
            if !config.progressTrigger.triggerOnce || thread.lastResurfacedAt == nil {
                return .progress(percent: percent, message: config.progressTrigger.message)
            }
        }

        // 3. Stuck trigger (days inactive)
        if config.stuckTrigger.enabled {
            let lastActivity = mostRecentActivity(tasks)
            let daysSince = Calendar.current.dateComponents(
                [.day],
                from: lastActivity,
                to: Date()
            ).day ?? 0

            if daysSince >= config.stuckTrigger.daysInactive {
                // Check cooldown
                if let lastResurfaced = thread.lastResurfacedAt {
                    let cooldownPassed = Calendar.current.dateComponents(
                        [.day],
                        from: lastResurfaced,
                        to: Date()
                    ).day ?? 0 >= config.stuckTrigger.cooldownDays

                    if !cooldownPassed { return nil }
                }

                return .stuck(days: daysSince, message: config.stuckTrigger.message)
            }
        }

        return nil
    }

    private func mostRecentActivity(_ tasks: [ThingsTaskStatus]) -> Date {
        tasks.map { $0.modificationDate }.max() ?? Date.distantPast
    }
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/ResurfaceTriggerService.swift
git commit -m "feat(service): add ResurfaceTriggerService for trigger evaluation"
```

---

## Task 8: Add DatabaseService Methods for Resurface

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`

**Step 1: Add method to get all task link IDs**

```swift
/// Get all Things task IDs from task_links table
func getAllTaskLinkIds() async throws -> [String] {
    guard let db = db else { throw DatabaseError.notConnected }

    let query = "SELECT things_task_id FROM task_links WHERE things_task_id IS NOT NULL AND things_task_id != ''"
    var ids: [String] = []

    for row in try db.prepare(query) {
        if let id = row[0] as? String {
            ids.append(id)
        }
    }

    return ids
}
```

**Step 2: Add method to update task link status**

```swift
/// Update task_links with status from Things
func updateTaskLinkStatus(
    thingsId: String,
    status: String,
    completedAt: Date?
) async throws {
    guard let db = db else { throw DatabaseError.notConnected }

    let now = ISO8601DateFormatter().string(from: Date())
    var completedStr: String? = nil
    if let date = completedAt {
        completedStr = ISO8601DateFormatter().string(from: date)
    }

    let query = """
        UPDATE task_links SET
            things_status = ?,
            things_completed_at = ?,
            last_synced_at = ?
        WHERE things_task_id = ?
    """

    try db.run(query, status, completedStr, now, thingsId)
}
```

**Step 3: Add method to get tasks for a thread**

```swift
/// Get task statuses for a specific thread
func fetchTaskIdsForThread(_ threadId: Int) async throws -> [String] {
    guard let db = db else { throw DatabaseError.notConnected }

    let query = "SELECT things_task_id FROM task_links WHERE discussion_thread_id = ? AND things_task_id IS NOT NULL"
    var ids: [String] = []

    for row in try db.prepare(query, threadId) {
        if let id = row[0] as? String {
            ids.append(id)
        }
    }

    return ids
}
```

**Step 4: Add method to resurface a thread**

```swift
/// Update thread to review status with resurface reason
func resurfaceThread(
    _ threadId: Int,
    reason: String
) async throws {
    guard let db = db else { throw DatabaseError.notConnected }

    let now = ISO8601DateFormatter().string(from: Date())

    let query = """
        UPDATE discussion_threads SET
            status = 'review',
            resurface_reason = ?,
            last_resurfaced_at = ?
        WHERE id = ?
    """

    try db.run(query, reason, now, threadId)
}
```

**Step 5: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 6: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(db): add resurface and task status methods to DatabaseService"
```

---

## Task 9: Update PlanningView with Sync Logic

**Files:**
- Modify: `SeleneChat/Sources/Views/PlanningView.swift`

**Step 1: Add service properties and state**

At the top of PlanningView, add:

```swift
@StateObject private var thingsStatusService = ThingsStatusService.shared
@StateObject private var triggerService = ResurfaceTriggerService.shared
@State private var isSyncing = false
@State private var lastSyncResult: SyncResult?
```

**Step 2: Add sync task to body**

In the `body` property's Group, add `.task` modifier after `.onAppear`:

```swift
.task {
    await syncThingsAndEvaluateTriggers()
}
```

**Step 3: Add the sync method**

```swift
private func syncThingsAndEvaluateTriggers() async {
    guard !isSyncing else { return }
    isSyncing = true
    defer { isSyncing = false }

    do {
        // 1. Get all tracked task IDs
        let taskIds = try await databaseService.getAllTaskLinkIds()
        guard !taskIds.isEmpty else { return }

        // 2. Sync statuses from Things
        let result = await thingsStatusService.syncAllTaskStatuses(taskIds: taskIds) { thingsId, status in
            try await databaseService.updateTaskLinkStatus(
                thingsId: thingsId,
                status: status.status,
                completedAt: status.completionDate
            )
        }
        lastSyncResult = result

        // 3. Evaluate triggers for active threads
        let threads = try await databaseService.fetchThreads(statuses: [.active])

        for thread in threads {
            let threadTaskIds = try await databaseService.fetchTaskIdsForThread(thread.id)
            guard !threadTaskIds.isEmpty else { continue }

            // Get current statuses for these tasks
            var taskStatuses: [ThingsTaskStatus] = []
            for taskId in threadTaskIds {
                if let status = try? await thingsStatusService.getTaskStatus(thingsId: taskId) {
                    taskStatuses.append(status)
                }
            }

            // Evaluate triggers
            if let trigger = triggerService.evaluateTriggers(thread: thread, tasks: taskStatuses) {
                try await databaseService.resurfaceThread(thread.id, reason: trigger.reasonCode)
                print("Resurfaced thread \(thread.id) with reason: \(trigger.reasonCode)")
            }
        }

    } catch {
        print("Sync failed: \(error)")
    }
}
```

**Step 4: Add sync indicator to header (optional)**

In the header HStack, add after the Settings button:

```swift
if isSyncing {
    ProgressView()
        .scaleEffect(0.7)
}
```

**Step 5: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 6: Commit**

```bash
git add SeleneChat/Sources/Views/PlanningView.swift
git commit -m "feat(ui): add Things status sync on Planning tab open"
```

---

## Task 10: Update Thread List Sorting

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift` (or wherever threads are fetched)

**Step 1: Update fetchThreads to handle review status**

Ensure the `fetchThreads` method includes review in the status filter and sorts review threads first:

```swift
/// Fetch threads with optional status filter, review status first
func fetchThreads(statuses: [ThreadStatus]? = nil) async throws -> [DiscussionThread] {
    guard let db = db else { throw DatabaseError.notConnected }

    var query = "SELECT * FROM discussion_threads"

    if let statuses = statuses {
        let statusStrings = statuses.map { "'\($0.rawValue)'" }.joined(separator: ", ")
        query += " WHERE status IN (\(statusStrings))"
    }

    // Sort: review first, then by created_at descending
    query += " ORDER BY CASE WHEN status = 'review' THEN 0 ELSE 1 END, created_at DESC"

    var threads: [DiscussionThread] = []
    for row in try db.prepare(query) {
        if let thread = try? DiscussionThread(from: row) {
            threads.append(thread)
        }
    }

    return threads
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -10`
Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(db): sort review status threads first in list"
```

---

## Task 11: Update BRANCH-STATUS.md

**Files:**
- Modify: `BRANCH-STATUS.md`

**Step 1: Update planning stage**

Mark "Implementation plan written" as complete:

```markdown
### Planning
- [x] Design doc exists and approved
- [x] Conflict check completed (no overlapping work)
- [x] Dependencies identified and noted
- [x] Branch and worktree created
- [x] Implementation plan written (superpowers:writing-plans)
```

**Step 2: Commit**

```bash
git add BRANCH-STATUS.md
git commit -m "chore: mark planning stage complete in BRANCH-STATUS"
```

---

## Task 12: Manual Testing

**No files to modify - verification steps**

**Step 1: Build and run SeleneChat**

```bash
cd SeleneChat && swift build && swift run
```

**Step 2: Create test data**

1. Open Planning tab
2. Create a planning thread (or use existing)
3. Create tasks in Things from that thread
4. Complete some tasks in Things

**Step 3: Verify sync**

1. Close and reopen Planning tab
2. Observe console for sync messages
3. Verify thread shows resurface message if triggers fire

**Step 4: Document results in BRANCH-STATUS.md Notes section**

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Database migration | Migration003, DatabaseService |
| 2 | DiscussionThread model | DiscussionThread.swift |
| 3 | ThingsTaskStatus model | ThingsTaskStatus.swift |
| 4 | ThingsStatusService | ThingsStatusService.swift |
| 5 | ResurfaceConfig model | ResurfaceConfig.swift |
| 6 | Yams dependency | Package.swift |
| 7 | ResurfaceTriggerService | ResurfaceTriggerService.swift |
| 8 | DatabaseService methods | DatabaseService.swift |
| 9 | PlanningView sync | PlanningView.swift |
| 10 | Thread list sorting | DatabaseService.swift |
| 11 | Update BRANCH-STATUS | BRANCH-STATUS.md |
| 12 | Manual testing | (verification) |

**Total commits:** 11 (plus any fixes discovered during testing)
