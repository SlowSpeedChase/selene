# Thread Workspace Phase 3: Feedback Loop — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the feedback loop so task completions in Things flow back into Selene, boost thread momentum, and power LLM "what's next" recommendations.

**Architecture:** All sync logic lives in Swift (SeleneChat). On-demand sync queries Things via existing `get-task-status.scpt` when the workspace opens. A new `thread_activity` table records events that the existing TypeScript `reconsolidate-threads.ts` uses for momentum calculation.

**Tech Stack:** Swift/SwiftUI (SeleneChat), SQLite (migrations), TypeScript (reconsolidate-threads.ts), AppleScript (get-task-status.scpt)

---

### Task 1: Database Migration — thread_activity table

**Files:**
- Create: `database/migrations/018_thread_activity.sql`

**Step 1: Write the migration SQL**

```sql
-- 018_thread_activity.sql
-- Records thread activity events for momentum calculation.
-- Task completions and note additions are tracked here so
-- reconsolidate-threads.ts can factor them into momentum scores.

CREATE TABLE IF NOT EXISTS thread_activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    activity_type TEXT NOT NULL CHECK(activity_type IN ('note_added', 'task_completed')),
    occurred_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_thread_activity_thread ON thread_activity(thread_id);
CREATE INDEX IF NOT EXISTS idx_thread_activity_recent ON thread_activity(occurred_at);
```

**Step 2: Apply the migration manually to verify**

Run: `sqlite3 ~/selene-data/selene.db < database/migrations/018_thread_activity.sql`
Expected: No errors. Verify with: `sqlite3 ~/selene-data/selene.db ".schema thread_activity"`

**Step 3: Commit**

```bash
git add database/migrations/018_thread_activity.sql
git commit -m "feat: add thread_activity table for momentum tracking"
```

---

### Task 2: DatabaseService — recordThreadActivity and ensureThreadActivityTable

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ThreadActivityTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/ThreadActivityTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class ThreadActivityTests: XCTestCase {

    func testRecordThreadActivityInsertsRow() async throws {
        let db = DatabaseService.shared

        // Use a known thread ID (thread 1 should exist in test DB)
        // Record a task_completed activity
        try await db.recordThreadActivity(threadId: 1, type: "task_completed")

        // Verify by reading back
        let activities = try await db.getRecentThreadActivity(threadId: 1, days: 1)
        XCTAssertTrue(activities.contains { $0.activityType == "task_completed" },
                       "Should have recorded a task_completed activity")
    }

    func testRecordThreadActivityRejectsInvalidType() async {
        let db = DatabaseService.shared

        do {
            try await db.recordThreadActivity(threadId: 1, type: "invalid_type")
            XCTFail("Should have thrown for invalid activity type")
        } catch {
            // Expected — CHECK constraint violation
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ThreadActivityTests`
Expected: FAIL — `recordThreadActivity` and `getRecentThreadActivity` don't exist yet

**Step 3: Write minimal implementation**

Add to `DatabaseService.swift` after the `markThreadTaskCompleted` method (around line 627):

```swift
    // MARK: - Thread Activity

    private let threadActivityTable = Table("thread_activity")
    private let activityId = SQLite.Expression<Int64>("id")
    private let activityThreadId = SQLite.Expression<Int64>("thread_id")
    private let activityType = SQLite.Expression<String>("activity_type")
    private let activityOccurredAt = SQLite.Expression<String>("occurred_at")

    /// Ensure thread_activity table exists (auto-migration)
    private func ensureThreadActivityTable() throws {
        guard let db = db else { return }
        let tableExists = try db.scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='thread_activity'"
        ) as? Int64 ?? 0

        if tableExists == 0 {
            try db.execute("""
                CREATE TABLE IF NOT EXISTS thread_activity (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    thread_id INTEGER NOT NULL,
                    activity_type TEXT NOT NULL CHECK(activity_type IN ('note_added', 'task_completed')),
                    occurred_at TEXT DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_thread_activity_thread ON thread_activity(thread_id);
                CREATE INDEX IF NOT EXISTS idx_thread_activity_recent ON thread_activity(occurred_at);
            """)
        }
    }

    /// Record a thread activity event (e.g., task_completed)
    func recordThreadActivity(threadId: Int64, type: String, timestamp: Date = Date()) async throws {
        guard let db = db else {
            throw DatabaseError.notConnected
        }

        try ensureThreadActivityTable()

        let dateStr = iso8601Formatter.string(from: timestamp)
        try db.run(threadActivityTable.insert(
            activityThreadId <- threadId,
            activityType <- type,
            activityOccurredAt <- dateStr
        ))
    }

    /// A simple struct for activity records
    struct ThreadActivityRecord {
        let id: Int64
        let threadId: Int64
        let activityType: String
        let occurredAt: Date
    }

    /// Get recent thread activity within a number of days
    func getRecentThreadActivity(threadId: Int64, days: Int) async throws -> [ThreadActivityRecord] {
        guard let db = db else {
            throw DatabaseError.notConnected
        }

        try ensureThreadActivityTable()

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = iso8601Formatter.string(from: cutoff)

        let query = threadActivityTable
            .filter(activityThreadId == threadId && activityOccurredAt >= cutoffStr)
            .order(activityOccurredAt.desc)

        var activities: [ThreadActivityRecord] = []
        for row in try db.prepare(query) {
            activities.append(ThreadActivityRecord(
                id: row[activityId],
                threadId: row[activityThreadId],
                activityType: row[activityType],
                occurredAt: parseDateString(row[activityOccurredAt]) ?? Date()
            ))
        }
        return activities
    }
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ThreadActivityTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift SeleneChat/Tests/SeleneChatTests/Services/ThreadActivityTests.swift
git commit -m "feat: add recordThreadActivity and getRecentThreadActivity to DatabaseService"
```

---

### Task 3: ThingsURLService — syncTaskStatuses

**Files:**
- Modify: `SeleneChat/Sources/Services/ThingsURLService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ThingsSyncTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/SeleneChatTests/Services/ThingsSyncTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class ThingsSyncTests: XCTestCase {

    func testParseTaskStatusResponseCompleted() {
        let json = """
        {"id": "ABC123", "status": "completed", "name": "Test Task", "completion_date": "2026-02-13", "modification_date": "2026-02-13", "creation_date": "2026-02-10", "project": null, "area": null, "tags": ["selene"]}
        """

        let result = ThingsURLService.parseTaskStatusResponse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "completed")
        XCTAssertEqual(result?.name, "Test Task")
        XCTAssertNotNil(result?.completionDate)
    }

    func testParseTaskStatusResponseOpen() {
        let json = """
        {"id": "DEF456", "status": "open", "name": "Open Task", "completion_date": null, "modification_date": "2026-02-13", "creation_date": "2026-02-10", "project": null, "area": null, "tags": []}
        """

        let result = ThingsURLService.parseTaskStatusResponse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "open")
        XCTAssertNil(result?.completionDate)
    }

    func testParseTaskStatusResponseError() {
        let json = """
        {"error": "Task not found: XYZ789"}
        """

        let result = ThingsURLService.parseTaskStatusResponse(json)
        XCTAssertNil(result, "Should return nil for error responses")
    }

    func testParseTaskStatusResponseInvalidJSON() {
        let result = ThingsURLService.parseTaskStatusResponse("not json")
        XCTAssertNil(result)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ThingsSyncTests`
Expected: FAIL — `parseTaskStatusResponse` doesn't exist yet

**Step 3: Write minimal implementation**

Add to `ThingsURLService.swift`:

```swift
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

                // Update title if we got one from Things
                // (title is transient, not stored — but useful for display refresh)

                if status.status == "completed" || status.status == "canceled" {
                    // Parse completion date
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

                    // Record activity for momentum
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
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ThingsSyncTests`
Expected: PASS (tests only cover parsing, not AppleScript execution)

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/ThingsURLService.swift SeleneChat/Tests/SeleneChatTests/Services/ThingsSyncTests.swift
git commit -m "feat: add Things task status sync to ThingsURLService"
```

---

### Task 4: ThreadWorkspaceView — call sync on appear

**Files:**
- Modify: `SeleneChat/Sources/Views/ThreadWorkspaceView.swift`

**Step 1: Add sync call to loadData()**

In `ThreadWorkspaceView.swift`, modify the `loadData()` method (line 345) to sync tasks after loading them:

Replace the existing `loadData()` with:

```swift
    private func loadData() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Load thread details
            thread = try await databaseService.getThreadById(threadId)

            guard let loadedThread = thread else {
                error = "Thread not found"
                return
            }

            // Load tasks for thread
            tasks = try await databaseService.getTasksForThread(threadId)

            // Sync incomplete tasks with Things (on-demand)
            let newlyCompleted = await ThingsURLService.shared.syncTaskStatuses(
                for: tasks,
                databaseService: databaseService
            )

            // Reload tasks if any were completed
            if !newlyCompleted.isEmpty {
                tasks = try await databaseService.getTasksForThread(threadId)
            }

            // Load notes for thread
            if let result = try await databaseService.getThreadByName(loadedThread.name) {
                notes = result.1
            }

            // Initialize chat VM with loaded data
            if chatViewModel == nil {
                chatViewModel = ThreadWorkspaceChatViewModel(
                    thread: loadedThread,
                    notes: notes,
                    tasks: tasks
                )
            } else {
                chatViewModel?.updateTasks(tasks)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
```

**Step 2: Run full test suite to verify no regressions**

Run: `cd SeleneChat && swift test`
Expected: All existing tests PASS

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Views/ThreadWorkspaceView.swift
git commit -m "feat: sync task completion from Things when workspace opens"
```

---

### Task 5: Extend reconsolidate-threads.ts — include thread_activity in momentum

**Files:**
- Modify: `src/workflows/reconsolidate-threads.ts`

**Step 1: Modify the calculateMomentum function**

In `reconsolidate-threads.ts`, replace the `calculateMomentum()` function (lines 186-224) with:

```typescript
/**
 * Calculate momentum scores for all active threads.
 * Formula: (notes_7_days * 2) + (notes_30_days * 1) + (tasks_completed_7_days * 3)
 */
function calculateMomentum(): number {
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

  // Check if thread_activity table exists
  const activityTableExists = db
    .prepare("SELECT COUNT(*) as count FROM sqlite_master WHERE type='table' AND name='thread_activity'")
    .get() as { count: number };

  // Get note counts per thread for 7-day and 30-day windows
  const momentumData = db
    .prepare(
      `SELECT
         t.id as thread_id,
         SUM(CASE WHEN tn.added_at >= ? THEN 1 ELSE 0 END) as notes_7_days,
         SUM(CASE WHEN tn.added_at >= ? THEN 1 ELSE 0 END) as notes_30_days
       FROM threads t
       LEFT JOIN thread_notes tn ON t.id = tn.thread_id
       WHERE t.status = 'active'
       GROUP BY t.id`
    )
    .all(sevenDaysAgo, thirtyDaysAgo) as MomentumData[];

  // Get task completion counts if table exists
  let taskCompletions: Record<number, number> = {};
  if (activityTableExists.count > 0) {
    const activityData = db
      .prepare(
        `SELECT thread_id, COUNT(*) as completed_count
         FROM thread_activity
         WHERE activity_type = 'task_completed'
           AND occurred_at >= ?
         GROUP BY thread_id`
      )
      .all(sevenDaysAgo) as { thread_id: number; completed_count: number }[];

    for (const row of activityData) {
      taskCompletions[row.thread_id] = row.completed_count;
    }
  }

  // Update momentum scores
  const updateStmt = db.prepare(
    `UPDATE threads SET momentum_score = ? WHERE id = ?`
  );

  let updated = 0;
  for (const data of momentumData) {
    const tasksCompleted = taskCompletions[data.thread_id] || 0;
    // Task completions weighted highest (3x) — progress feels good
    const momentum =
      (data.notes_7_days * 2) + (data.notes_30_days * 1) + (tasksCompleted * 3);

    updateStmt.run(momentum, data.thread_id);
    updated++;
  }

  log.info({ threadsUpdated: updated }, 'Momentum scores calculated');
  return updated;
}
```

**Step 2: Run the workflow to verify**

Run: `npx ts-node src/workflows/reconsolidate-threads.ts`
Expected: Completes without errors. Log shows "Momentum scores calculated".

**Step 3: Commit**

```bash
git add src/workflows/reconsolidate-threads.ts
git commit -m "feat: include task completions in thread momentum calculation"
```

---

### Task 6: ThreadWorkspacePromptBuilder — "What's next" detection and prompt

**Files:**
- Modify: `SeleneChat/Sources/Services/ThreadWorkspacePromptBuilder.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ThreadWorkspacePromptBuilderTests.swift`

**Step 1: Write the failing test**

Add to `ThreadWorkspacePromptBuilderTests.swift`:

```swift
    // MARK: - What's Next Tests

    func testIsWhatsNextQueryDetectsVariations() {
        let builder = ThreadWorkspacePromptBuilder()

        XCTAssertTrue(builder.isWhatsNextQuery("what's next"))
        XCTAssertTrue(builder.isWhatsNextQuery("What's next?"))
        XCTAssertTrue(builder.isWhatsNextQuery("what should I do next"))
        XCTAssertTrue(builder.isWhatsNextQuery("What should I work on?"))
        XCTAssertTrue(builder.isWhatsNextQuery("what do I do now"))
        XCTAssertFalse(builder.isWhatsNextQuery("break down the auth task"))
        XCTAssertFalse(builder.isWhatsNextQuery("tell me about this thread"))
    }

    func testBuildWhatsNextPromptIncludesTaskState() {
        let thread = Thread.mock(
            name: "ADHD System",
            why: "Build tools for executive function",
            summary: "Phase 1 complete"
        )

        let openTask = ThreadTask.mock(thingsTaskId: "T1", title: "Research time-blocking")
        let completedTask = ThreadTask.mock(thingsTaskId: "T2", title: "Write principles doc", completedAt: Date())

        let notes = [
            Note.mock(id: 1, title: "ADHD Research", content: "Focus on externalization")
        ]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildWhatsNextPrompt(thread: thread, notes: notes, tasks: [openTask, completedTask])

        XCTAssertTrue(prompt.contains("Research time-blocking"), "Should include open task")
        XCTAssertTrue(prompt.contains("Write principles doc"), "Should include completed task")
        XCTAssertTrue(prompt.contains("recommend"), "Should ask LLM to recommend")
    }
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ThreadWorkspacePromptBuilderTests`
Expected: FAIL — `isWhatsNextQuery` and `buildWhatsNextPrompt` don't exist

**Step 3: Write minimal implementation**

Add to `ThreadWorkspacePromptBuilder.swift` after the existing `buildFollowUpPrompt` method:

```swift
    // MARK: - What's Next

    /// Patterns that indicate a "what's next" query
    private let whatsNextPatterns: [String] = [
        "what's next",
        "whats next",
        "what should i do",
        "what should i work on",
        "what do i do",
        "what to do next",
        "what now",
        "next step",
        "next steps",
    ]

    /// Detect if a query is asking "what's next"
    func isWhatsNextQuery(_ query: String) -> Bool {
        let lowered = query.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespaces)
        return whatsNextPatterns.contains { lowered.contains($0) }
    }

    /// Build a specialized prompt for "what's next" recommendations
    func buildWhatsNextPrompt(thread: Thread, notes: [Note], tasks: [ThreadTask]) -> String {
        let threadContext = contextBuilder.buildDeepDiveContext(thread: thread, notes: notes)
        let openTasks = tasks.filter { !$0.isCompleted }
        let completedTasks = tasks.filter { $0.isCompleted }

        var taskList = ""
        if !openTasks.isEmpty {
            taskList += "Open tasks:\n"
            for task in openTasks {
                let title = task.title ?? task.thingsTaskId
                let age = Calendar.current.dateComponents([.day], from: task.createdAt, to: Date()).day ?? 0
                taskList += "- \(title) (created \(age) days ago)\n"
            }
        }
        if !completedTasks.isEmpty {
            taskList += "\nRecently completed:\n"
            for task in completedTasks.prefix(5) {
                let title = task.title ?? task.thingsTaskId
                taskList += "- \(title) (done)\n"
            }
        }

        return """
        You are helping someone with ADHD decide what to work on next in their "\(thread.name)" thread.

        \(threadContext)

        ## Task State
        \(taskList.isEmpty ? "No tasks linked to this thread yet." : taskList)

        Based on the thread context, open tasks, and what's been completed, recommend ONE specific task to tackle next. Explain briefly why (consider energy level, dependencies, and momentum). Keep it under 100 words.

        If there are no open tasks, suggest what the logical next action would be based on the thread's current state.
        """
    }
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ThreadWorkspacePromptBuilderTests`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/ThreadWorkspacePromptBuilder.swift SeleneChat/Tests/SeleneChatTests/Services/ThreadWorkspacePromptBuilderTests.swift
git commit -m "feat: add 'what's next' detection and prompt to ThreadWorkspacePromptBuilder"
```

---

### Task 7: ThreadWorkspaceChatViewModel — route "what's next" queries

**Files:**
- Modify: `SeleneChat/Sources/ViewModels/ThreadWorkspaceChatViewModel.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/ViewModels/ThreadWorkspaceChatViewModelTests.swift`

**Step 1: Write the failing test**

Add to `ThreadWorkspaceChatViewModelTests.swift`:

```swift
    func testBuildPromptUsesWhatsNextForMatchingQuery() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(thread: thread, notes: [], tasks: [])

        let prompt = vm.buildPrompt(for: "what's next?")
        XCTAssertTrue(prompt.contains("recommend"), "Should use what's next prompt")
    }

    func testBuildPromptUsesRegularForNonMatchingQuery() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(thread: thread, notes: [], tasks: [])

        let prompt = vm.buildPrompt(for: "break down the auth task")
        XCTAssertFalse(prompt.contains("recommend ONE specific task"),
                       "Should NOT use what's next prompt for regular queries")
    }
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ThreadWorkspaceChatViewModelTests`
Expected: FAIL — `buildPrompt` doesn't route to `buildWhatsNextPrompt` yet

**Step 3: Modify buildPrompt to check for "what's next"**

In `ThreadWorkspaceChatViewModel.swift`, replace the `buildPrompt(for:)` method (lines 138-161):

```swift
    /// Build the appropriate prompt for the current conversation state.
    func buildPrompt(for query: String) -> String {
        // Check for "what's next" query first
        if promptBuilder.isWhatsNextQuery(query) {
            return promptBuilder.buildWhatsNextPrompt(
                thread: thread,
                notes: notes,
                tasks: tasks
            )
        }

        // If no prior conversation, use initial prompt
        let priorMessages = messages.filter { $0.role != .system }
        let hasHistory = priorMessages.contains { $0.role == .assistant }

        if hasHistory {
            let history = buildConversationHistory()
            return promptBuilder.buildFollowUpPrompt(
                thread: thread,
                notes: notes,
                tasks: tasks,
                conversationHistory: history,
                currentQuery: query
            )
        } else {
            return promptBuilder.buildInitialPrompt(
                thread: thread,
                notes: notes,
                tasks: tasks
            )
        }
    }
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ThreadWorkspaceChatViewModelTests`
Expected: PASS

**Step 5: Run full test suite**

Run: `cd SeleneChat && swift test`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add SeleneChat/Sources/ViewModels/ThreadWorkspaceChatViewModel.swift SeleneChat/Tests/SeleneChatTests/ViewModels/ThreadWorkspaceChatViewModelTests.swift
git commit -m "feat: route 'what's next' queries to specialized prompt in workspace chat"
```

---

### Task 8: Build, install, and manual verification

**Files:** None (verification only)

**Step 1: Build the app**

Run: `cd SeleneChat && ./build-app.sh && cp -R .build/release/SeleneChat.app /Applications/`
Expected: Build succeeds, app installs

**Step 2: Manual verification checklist**

1. Open SeleneChat from menu bar
2. Navigate to a thread workspace that has linked tasks
3. Verify: tasks show current completion status from Things
4. Complete a task in Things, close and reopen workspace — verify it shows as done
5. Type "what's next" in workspace chat — verify LLM recommends a task
6. Check momentum: the thread should have slightly higher momentum after task completion (wait for next reconsolidation run, or run manually: `npx ts-node src/workflows/reconsolidate-threads.ts`)

**Step 3: Run full test suite one final time**

Run: `cd SeleneChat && swift test`
Expected: All tests PASS

**Step 4: Final commit with design doc status update**

Update `docs/plans/2026-02-13-thread-workspace-phase3-design.md` status from Ready to Done.
Update `docs/plans/INDEX.md` — move from Ready to Done.
Update `docs/plans/2026-02-06-thread-workspace-design.md` status to Done (all phases complete).
Update `.claude/PROJECT-STATUS.md` — add Phase 3 to recent completions.

```bash
git add docs/plans/ .claude/PROJECT-STATUS.md
git commit -m "docs: mark Thread Workspace Phase 3 as complete"
```
