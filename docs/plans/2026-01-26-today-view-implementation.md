# Today View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a "Today" dashboard as the default landing page in SeleneChat, showing new captures and heating threads.

**Architecture:** New TodayView with TodayViewModel, TodayService for queries. Modify ContentView to add tab and make it default. Modify ChatView to accept pre-filled query.

**Tech Stack:** Swift 5.9+, SwiftUI, SQLite.swift

---

## Task 1: Create TodayModels

**Files:**
- Create: `SeleneChat/Sources/Models/TodayModels.swift`

**Step 1: Create the models file**

```swift
import Foundation

/// A note with optional thread connection for Today view
struct NoteWithThread: Identifiable {
    let id: Int64
    let title: String
    let preview: String
    let createdAt: Date
    let threadName: String?
    let threadId: Int64?

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}

/// Thread summary for Heating Up column
struct ThreadSummary: Identifiable {
    let id: Int64
    let name: String
    let summary: String
    let noteCount: Int
    let momentumScore: Double
    let recentNoteTitles: [String]

    var summaryPreview: String {
        String(summary.prefix(100))
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Models/TodayModels.swift
git commit -m "feat(today): add NoteWithThread and ThreadSummary models"
```

---

## Task 2: Create TodayService

**Files:**
- Create: `SeleneChat/Sources/Services/TodayService.swift`

**Step 1: Create the service with database queries**

```swift
import Foundation
import SQLite

class TodayService {
    private let db: Connection

    // Tables
    private let rawNotes = Table("raw_notes")
    private let threadsTable = Table("threads")
    private let threadNotesTable = Table("thread_notes")

    // raw_notes columns
    private let noteId = Expression<Int64>("id")
    private let noteTitle = Expression<String>("title")
    private let noteContent = Expression<String>("content")
    private let noteCreatedAt = Expression<String>("created_at")
    private let noteTestRun = Expression<String?>("test_run")

    // threads columns
    private let threadId = Expression<Int64>("id")
    private let threadName = Expression<String>("name")
    private let threadSummary = Expression<String?>("summary")
    private let threadStatus = Expression<String>("status")
    private let threadNoteCount = Expression<Int64>("note_count")
    private let threadMomentumScore = Expression<Double?>("momentum_score")

    // thread_notes columns
    private let tnThreadId = Expression<Int64>("thread_id")
    private let tnRawNoteId = Expression<Int64>("raw_note_id")

    init(db: Connection) {
        self.db = db
    }

    /// Get notes created after cutoff date, with thread info if connected
    func getNewCaptures(since cutoff: Date, limit: Int = 10) throws -> [NoteWithThread] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let cutoffString = dateFormatter.string(from: cutoff)

        // Query notes with optional thread join
        let query = rawNotes
            .select(
                rawNotes[noteId],
                rawNotes[noteTitle],
                rawNotes[noteContent],
                rawNotes[noteCreatedAt],
                threadsTable[threadId].asOptional,
                threadsTable[threadName].asOptional
            )
            .join(.leftOuter, threadNotesTable, on: rawNotes[noteId] == threadNotesTable[tnRawNoteId])
            .join(.leftOuter, threadsTable, on: threadNotesTable[tnThreadId] == threadsTable[threadId])
            .filter(rawNotes[noteCreatedAt] > cutoffString)
            .filter(rawNotes[noteTestRun] == nil)
            .order(rawNotes[noteCreatedAt].desc)
            .limit(limit)

        var results: [NoteWithThread] = []

        for row in try db.prepare(query) {
            let createdAtString = row[rawNotes[noteCreatedAt]]
            let createdAt = dateFormatter.date(from: createdAtString) ?? Date()
            let content = row[rawNotes[noteContent]]
            let preview = String(content.prefix(80))

            let note = NoteWithThread(
                id: row[rawNotes[noteId]],
                title: row[rawNotes[noteTitle]],
                preview: preview,
                createdAt: createdAt,
                threadName: row[threadsTable[threadName].asOptional],
                threadId: row[threadsTable[threadId].asOptional]
            )
            results.append(note)
        }

        return results
    }

    /// Get threads with momentum, sorted by score descending
    func getHeatingUpThreads(limit: Int = 5) throws -> [ThreadSummary] {
        let query = threadsTable
            .filter(threadStatus == "active")
            .filter(threadMomentumScore > 0)
            .order(threadMomentumScore.desc)
            .limit(limit)

        var results: [ThreadSummary] = []

        for row in try db.prepare(query) {
            let id = row[threadId]
            let recentTitles = try getRecentNoteTitles(forThread: id, limit: 3)

            let thread = ThreadSummary(
                id: id,
                name: row[threadName],
                summary: row[threadSummary] ?? "",
                noteCount: Int(row[threadNoteCount]),
                momentumScore: row[threadMomentumScore] ?? 0,
                recentNoteTitles: recentTitles
            )
            results.append(thread)
        }

        return results
    }

    /// Get recent note titles for a thread
    private func getRecentNoteTitles(forThread threadId: Int64, limit: Int = 3) throws -> [String] {
        let query = rawNotes
            .select(rawNotes[noteTitle])
            .join(threadNotesTable, on: rawNotes[noteId] == threadNotesTable[tnRawNoteId])
            .filter(threadNotesTable[tnThreadId] == threadId)
            .order(rawNotes[noteCreatedAt].desc)
            .limit(limit)

        var titles: [String] = []
        for row in try db.prepare(query) {
            titles.append(row[rawNotes[noteTitle]])
        }
        return titles
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/TodayService.swift
git commit -m "feat(today): add TodayService with database queries"
```

---

## Task 3: Create TodayViewModel

**Files:**
- Create: `SeleneChat/Sources/Services/TodayViewModel.swift`

**Step 1: Create the view model**

```swift
import Foundation
import SwiftUI

@MainActor
class TodayViewModel: ObservableObject {
    @Published var newCaptures: [NoteWithThread] = []
    @Published var heatingUpThreads: [ThreadSummary] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedNote: Note?

    private var todayService: TodayService?
    private var lastRefresh: Date?

    private let lastOpenKey = "lastAppOpen"

    func configure(with db: SQLite.Connection) {
        self.todayService = TodayService(db: db)
    }

    /// Calculate cutoff: max(24h ago, last app open)
    func getNewCutoff() -> Date {
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let lastOpen = UserDefaults.standard.object(forKey: lastOpenKey) as? Date ?? Date.distantPast
        return min(twentyFourHoursAgo, lastOpen)
    }

    /// Record current time as last app open
    func recordAppOpen() {
        UserDefaults.standard.set(Date(), forKey: lastOpenKey)
    }

    /// Refresh data from database
    func refresh() async {
        guard let service = todayService else {
            error = "Service not configured"
            return
        }

        isLoading = true
        error = nil

        do {
            let cutoff = getNewCutoff()
            newCaptures = try service.getNewCaptures(since: cutoff)
            heatingUpThreads = try service.getHeatingUpThreads()
            lastRefresh = Date()
        } catch {
            self.error = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Check if refresh needed (>5 min since last)
    func shouldRefresh() -> Bool {
        guard let last = lastRefresh else { return true }
        return Date().timeIntervalSince(last) > 300
    }

    /// Whether both columns are empty
    var isEmpty: Bool {
        newCaptures.isEmpty && heatingUpThreads.isEmpty
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/TodayViewModel.swift
git commit -m "feat(today): add TodayViewModel with refresh logic"
```

---

## Task 4: Create TodayView UI

**Files:**
- Create: `SeleneChat/Sources/Views/TodayView.swift`

**Step 1: Create the main view**

```swift
import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @EnvironmentObject var databaseService: DatabaseService

    var onThreadSelected: ((ThreadSummary) -> Void)?
    var onNoteThreadTap: ((NoteWithThread) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Today")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
            .padding()

            Divider()

            // Content
            if viewModel.isLoading && viewModel.newCaptures.isEmpty {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.isEmpty {
                emptyStateView
            } else {
                columnsView
            }
        }
        .onAppear {
            if let db = databaseService.db {
                viewModel.configure(with: db)
            }
            Task {
                await viewModel.refresh()
                viewModel.recordAppOpen()
            }
        }
    }

    // MARK: - Columns

    private var columnsView: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left: New Captures
            NewCapturesColumn(
                notes: viewModel.newCaptures,
                onNoteTap: { note in
                    // TODO: Open note detail
                },
                onThreadTap: { note in
                    onNoteThreadTap?(note)
                }
            )

            // Right: Heating Up
            HeatingUpColumn(
                threads: viewModel.heatingUpThreads,
                onThreadTap: { thread in
                    onThreadSelected?(thread)
                }
            )
        }
        .padding()
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading...")
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load today's view")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("All caught up")
                .font(.title2)
                .fontWeight(.semibold)
            Text("No new notes since yesterday, and no threads are heating up right now.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            HStack(spacing: 20) {
                Button("Capture a thought") {
                    // TODO: Open Drafts
                }
                Button("Browse past notes") {
                    // TODO: Navigate to Search
                }
            }
            Spacer()
        }
    }
}

// MARK: - New Captures Column

struct NewCapturesColumn: View {
    let notes: [NoteWithThread]
    let onNoteTap: (NoteWithThread) -> Void
    let onThreadTap: (NoteWithThread) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW CAPTURES")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if notes.isEmpty {
                emptyState
            } else {
                ForEach(notes) { note in
                    NoteCaptureCard(
                        note: note,
                        onTap: { onNoteTap(note) },
                        onThreadTap: { onThreadTap(note) }
                    )
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No new notes since yesterday")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Note Card

struct NoteCaptureCard: View {
    let note: NoteWithThread
    let onTap: () -> Void
    let onThreadTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(note.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Preview
            Text(note.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Thread link
            if let threadName = note.threadName {
                Button(action: onThreadTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                        Text("🔥")
                        Text(threadName)
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Heating Up Column

struct HeatingUpColumn: View {
    let threads: [ThreadSummary]
    let onThreadTap: (ThreadSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HEATING UP")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if threads.isEmpty {
                emptyState
            } else {
                ForEach(threads) { thread in
                    ThreadCard(thread: thread)
                        .onTapGesture { onThreadTap(thread) }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No threads heating up right now")
                .foregroundColor(.secondary)
            Text("Threads gain momentum when you add notes to the same line of thinking.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Thread Card

struct ThreadCard: View {
    let thread: ThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("🔥")
                Text(thread.name)
                    .font(.headline)
                Spacer()
                Text("\(thread.noteCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Summary
            if !thread.summary.isEmpty {
                Text(thread.summaryPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Recent notes
            if !thread.recentNoteTitles.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(thread.recentNoteTitles, id: \.self) { title in
                        HStack(spacing: 4) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(title)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}
```

**Step 2: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Views/TodayView.swift
git commit -m "feat(today): add TodayView with columns and cards"
```

---

## Task 5: Update ContentView for Today Tab

**Files:**
- Modify: `SeleneChat/Sources/App/ContentView.swift`

**Step 1: Add Today to NavigationItem enum**

In ContentView.swift, update the `NavigationItem` enum:

```swift
enum NavigationItem: String, CaseIterable {
    case today = "Today"      // NEW - first position
    case chat = "Chat"
    case search = "Search"
    case planning = "Planning"

    var icon: String {
        switch self {
        case .today: return "sun.horizon.fill"  // NEW
        case .chat: return "message.fill"
        case .search: return "magnifyingglass"
        case .planning: return "list.bullet.clipboard"
        }
    }
}
```

**Step 2: Change default selection to .today**

```swift
@State private var selectedView: NavigationItem = .today  // Changed from .chat
```

**Step 3: Add state for pending thread query**

```swift
@State private var pendingThreadQuery: String?
```

**Step 4: Add Today case to detail switch**

Update the detail section to handle `.today`:

```swift
} detail: {
    switch selectedView {
    case .today:
        TodayView(
            onThreadSelected: { thread in
                pendingThreadQuery = "What's happening with \(thread.name)?"
                selectedView = .chat
            },
            onNoteThreadTap: { note in
                if let threadName = note.threadName {
                    pendingThreadQuery = "What's happening with \(threadName)?"
                    selectedView = .chat
                }
            }
        )
    case .chat:
        ChatView(initialQuery: pendingThreadQuery)
            .onAppear { pendingThreadQuery = nil }
    case .search:
        SearchView()
    case .planning:
        PlanningView()
    }
}
```

**Step 5: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 6: Commit**

```bash
git add SeleneChat/Sources/App/ContentView.swift
git commit -m "feat(today): add Today tab as default landing page"
```

---

## Task 6: Update ChatView to Accept Initial Query

**Files:**
- Modify: `SeleneChat/Sources/Views/ChatView.swift`

**Step 1: Add initialQuery parameter**

At the top of ChatView struct, add:

```swift
var initialQuery: String? = nil
```

**Step 2: Handle initial query on appear**

In the `.onAppear` modifier, add logic to prefill the input:

```swift
.onAppear {
    if let query = initialQuery, !query.isEmpty {
        messageText = query
    }
    #if DEBUG
    DebugLogger.shared.log(.nav, "Appeared: ChatView")
    ActionTracker.shared.track(action: "viewAppeared", params: ["view": "ChatView"])
    #endif
}
```

**Step 3: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 4: Commit**

```bash
git add SeleneChat/Sources/Views/ChatView.swift
git commit -m "feat(chat): accept initialQuery parameter for prefilled input"
```

---

## Task 7: Fix SQLite Import in TodayViewModel

**Files:**
- Modify: `SeleneChat/Sources/Services/TodayViewModel.swift`

**Step 1: Add SQLite import**

At the top of the file, add:

```swift
import SQLite
```

**Step 2: Verify it compiles**

Run: `cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat && swift build 2>&1 | tail -5`

Expected: `Build complete!`

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/TodayViewModel.swift
git commit -m "fix(today): add SQLite import to TodayViewModel"
```

---

## Task 8: Manual Testing

**Step 1: Build and run the app**

```bash
cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat
swift build
swift run
```

**Step 2: Verify Today tab is default**

- App should open to Today view
- Should see two columns (or empty state)

**Step 3: Test interactions**

- Click a thread card → should navigate to Chat with prefilled query
- Click a note's thread link → should navigate to Chat
- Click refresh button → should reload data

**Step 4: Test edge cases**

- Both columns empty → "All caught up" message
- Error state → shows error with retry button

---

## Task 9: Final Commit and Summary

**Step 1: Verify all changes compile**

```bash
cd /Users/chaseeasterling/selene/.worktrees/today-view/SeleneChat
swift build
```

**Step 2: Review git log**

```bash
git log --oneline -10
```

Should show commits for:
- TodayModels
- TodayService
- TodayViewModel
- TodayView
- ContentView update
- ChatView update

---

## Summary

| Task | Files | Purpose |
|------|-------|---------|
| 1 | TodayModels.swift | Data models for notes and threads |
| 2 | TodayService.swift | Database queries |
| 3 | TodayViewModel.swift | State management, refresh logic |
| 4 | TodayView.swift | UI with columns and cards |
| 5 | ContentView.swift | Add tab, make default |
| 6 | ChatView.swift | Accept initialQuery |
| 7 | TodayViewModel.swift | Fix import |
| 8 | Manual testing | Verify functionality |
| 9 | Final verification | All tests pass |
