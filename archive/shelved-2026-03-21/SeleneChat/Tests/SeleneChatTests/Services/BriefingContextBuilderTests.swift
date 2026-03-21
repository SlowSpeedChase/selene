import SeleneShared
import XCTest
@testable import SeleneChat

final class BriefingContextBuilderTests: XCTestCase {

    let builder = BriefingContextBuilder()

    // MARK: - What Changed Context

    func testWhatChangedContextIncludesNoteContent() {
        let note = Note.mock(id: 1, title: "Deep Work Planning", content: "I want to block mornings for creative work")
        let thread = Thread.mock(id: 5, name: "Focus Systems", summary: "Strategies for sustained attention")

        let context = builder.buildWhatChangedContext(note: note, thread: thread, relatedNotes: [], tasks: [], memories: [])

        XCTAssertTrue(context.contains("Deep Work Planning"))
        XCTAssertTrue(context.contains("I want to block mornings"))
        XCTAssertTrue(context.contains("Focus Systems"))
        XCTAssertTrue(context.contains("Strategies for sustained attention"))
    }

    func testWhatChangedContextIncludesRelatedNotes() {
        let note = Note.mock(id: 1, title: "Main Note")
        let thread = Thread.mock(id: 5, name: "Thread")
        let related = [
            Note.mock(id: 2, title: "Related Note A", content: "Content A"),
            Note.mock(id: 3, title: "Related Note B", content: "Content B")
        ]

        let context = builder.buildWhatChangedContext(note: note, thread: thread, relatedNotes: related, tasks: [], memories: [])

        XCTAssertTrue(context.contains("Related Note A"))
        XCTAssertTrue(context.contains("Related Note B"))
    }

    func testWhatChangedContextIncludesConceptsAndEnergy() {
        let note = Note.mock(id: 1, title: "Test", concepts: ["focus", "productivity"], primaryTheme: "work", energyLevel: "high")

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: [], memories: [])

        XCTAssertTrue(context.contains("focus"))
        XCTAssertTrue(context.contains("productivity"))
        XCTAssertTrue(context.contains("high"))
        XCTAssertTrue(context.contains("work"))
    }

    func testWhatChangedContextWithNilThread() {
        let note = Note.mock(id: 1, title: "Standalone Note", content: "Some content")

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: [], memories: [])

        XCTAssertTrue(context.contains("Standalone Note"))
        XCTAssertTrue(context.contains("Some content"))
        XCTAssertFalse(context.contains("Parent Thread"))
    }

    func testWhatChangedContextLimitsRelatedNotesToThree() {
        let note = Note.mock(id: 1, title: "Main Note")
        let related = (2...6).map { Note.mock(id: $0, title: "Related \($0)", content: "Content \($0)") }

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: related, tasks: [], memories: [])

        XCTAssertTrue(context.contains("Related 2"))
        XCTAssertTrue(context.contains("Related 3"))
        XCTAssertTrue(context.contains("Related 4"))
        XCTAssertFalse(context.contains("Related 5"))
        XCTAssertFalse(context.contains("Related 6"))
    }

    // MARK: - Needs Attention Context

    func testNeedsAttentionContextIncludesThreadDetails() {
        let thread = Thread.mock(id: 5, name: "Stalled Thread", why: "Understanding focus patterns", summary: "Deep work strategies")
        let recentNotes = [Note.mock(id: 1, title: "Last Note", content: "Was working on X")]

        let context = builder.buildNeedsAttentionContext(thread: thread, recentNotes: recentNotes, tasks: [], memories: [])

        XCTAssertTrue(context.contains("Stalled Thread"))
        XCTAssertTrue(context.contains("Understanding focus patterns"))
        XCTAssertTrue(context.contains("Last Note"))
    }

    func testNeedsAttentionContextIncludesTasks() {
        let thread = Thread.mock(id: 5, name: "Thread")
        let tasks = [
            ThreadTask.mock(id: 1, threadId: 5, title: "Review notes"),
            ThreadTask.mock(id: 2, threadId: 5, title: "Done task", completedAt: Date())
        ]

        let context = builder.buildNeedsAttentionContext(thread: thread, recentNotes: [], tasks: tasks, memories: [])

        XCTAssertTrue(context.contains("Review notes"))
        XCTAssertFalse(context.contains("Done task"))  // Completed tasks excluded
    }

    func testNeedsAttentionContextIncludesStatusAndMomentum() {
        let thread = Thread.mock(id: 5, name: "Active Thread", status: "active", momentumScore: 0.8)

        let context = builder.buildNeedsAttentionContext(thread: thread, recentNotes: [], tasks: [], memories: [])

        XCTAssertTrue(context.contains("active"))
        XCTAssertTrue(context.contains("0.8"))
    }

    func testNeedsAttentionContextLimitsRecentNotesToThree() {
        let thread = Thread.mock(id: 5, name: "Thread")
        let recentNotes = (1...5).map { Note.mock(id: $0, title: "Note \($0)", content: "Content \($0)") }

        let context = builder.buildNeedsAttentionContext(thread: thread, recentNotes: recentNotes, tasks: [], memories: [])

        XCTAssertTrue(context.contains("Note 1"))
        XCTAssertTrue(context.contains("Note 2"))
        XCTAssertTrue(context.contains("Note 3"))
        XCTAssertFalse(context.contains("Note 4"))
        XCTAssertFalse(context.contains("Note 5"))
    }

    // MARK: - Connection Context

    func testConnectionContextIncludesBothNotes() {
        let noteA = Note.mock(id: 1, title: "Note A", content: "Content about energy")
        let noteB = Note.mock(id: 7, title: "Note B", content: "Content about routines")
        let threadA = Thread.mock(id: 5, name: "Focus Systems")
        let threadB = Thread.mock(id: 8, name: "Daily Habits")

        let context = builder.buildConnectionContext(
            noteA: noteA, threadA: threadA,
            noteB: noteB, threadB: threadB,
            relatedToA: [], relatedToB: [],
            tasks: [], memories: []
        )

        XCTAssertTrue(context.contains("Note A"))
        XCTAssertTrue(context.contains("Note B"))
        XCTAssertTrue(context.contains("Focus Systems"))
        XCTAssertTrue(context.contains("Daily Habits"))
    }

    func testConnectionContextHandlesNilThreads() {
        let noteA = Note.mock(id: 1, title: "Note A", content: "Content A")
        let noteB = Note.mock(id: 2, title: "Note B", content: "Content B")

        let context = builder.buildConnectionContext(
            noteA: noteA, threadA: nil,
            noteB: noteB, threadB: nil,
            relatedToA: [], relatedToB: [],
            tasks: [], memories: []
        )

        XCTAssertTrue(context.contains("Unthreaded"))
    }

    func testConnectionContextIncludesRelatedNotes() {
        let noteA = Note.mock(id: 1, title: "Note A", content: "Content A")
        let noteB = Note.mock(id: 2, title: "Note B", content: "Content B")
        let relatedToA = [Note.mock(id: 3, title: "Related to A", content: "Related content A")]
        let relatedToB = [Note.mock(id: 4, title: "Related to B", content: "Related content B")]

        let context = builder.buildConnectionContext(
            noteA: noteA, threadA: nil,
            noteB: noteB, threadB: nil,
            relatedToA: relatedToA, relatedToB: relatedToB,
            tasks: [], memories: []
        )

        XCTAssertTrue(context.contains("Related to A"))
        XCTAssertTrue(context.contains("Related to B"))
    }

    func testConnectionContextIncludesConcepts() {
        let noteA = Note.mock(id: 1, title: "Note A", concepts: ["focus", "flow"])
        let noteB = Note.mock(id: 2, title: "Note B", concepts: ["routine", "habit"])

        let context = builder.buildConnectionContext(
            noteA: noteA, threadA: nil,
            noteB: noteB, threadB: nil,
            relatedToA: [], relatedToB: [],
            tasks: [], memories: []
        )

        XCTAssertTrue(context.contains("focus"))
        XCTAssertTrue(context.contains("flow"))
        XCTAssertTrue(context.contains("routine"))
        XCTAssertTrue(context.contains("habit"))
    }

    // MARK: - System Prompt

    func testSystemPromptForWhatChanged() {
        let prompt = builder.buildSystemPrompt(for: .whatChanged)
        XCTAssertTrue(prompt.contains("Selene"))
        XCTAssertTrue(prompt.contains("morning briefing"))
        XCTAssertTrue(prompt.contains("Don't summarize"))
    }

    func testSystemPromptForNeedsAttention() {
        let prompt = builder.buildSystemPrompt(for: .needsAttention)
        XCTAssertTrue(prompt.contains("stalled"))
    }

    func testSystemPromptForConnection() {
        let prompt = builder.buildSystemPrompt(for: .connection)
        XCTAssertTrue(prompt.contains("connection"))
    }

    // MARK: - Memories

    func testContextIncludesMemories() {
        let note = Note.mock(id: 1, title: "Test")
        let memories = [
            ConversationMemory(id: 1, content: "User prefers morning work", memoryType: .preference, confidence: 0.9)
        ]

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: [], memories: memories)

        XCTAssertTrue(context.contains("User prefers morning work"))
        XCTAssertTrue(context.contains("preference"))
    }

    func testMemoriesLimitedToFive() {
        let note = Note.mock(id: 1, title: "Test")
        let memories = (1...8).map {
            ConversationMemory(id: Int64($0), content: "Memory \($0)", memoryType: .fact, confidence: 0.9)
        }

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: [], memories: memories)

        XCTAssertTrue(context.contains("Memory 1"))
        XCTAssertTrue(context.contains("Memory 5"))
        XCTAssertFalse(context.contains("Memory 6"))
    }

    // MARK: - Tasks Formatting

    func testEmptyTasksProducesNoSection() {
        let note = Note.mock(id: 1, title: "Test")

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: [], memories: [])

        XCTAssertFalse(context.contains("Open Tasks"))
    }

    func testTasksWithOnlyCompletedProducesNoSection() {
        let note = Note.mock(id: 1, title: "Test")
        let tasks = [
            ThreadTask.mock(id: 1, threadId: 1, title: "Completed task", completedAt: Date())
        ]

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: tasks, memories: [])

        XCTAssertFalse(context.contains("Open Tasks"))
    }

    func testTaskWithoutTitleFallsBackToThingsId() {
        let note = Note.mock(id: 1, title: "Test")
        let tasks = [
            ThreadTask.mock(id: 1, threadId: 1, title: nil, completedAt: nil)
        ]

        let context = builder.buildWhatChangedContext(note: note, thread: nil, relatedNotes: [], tasks: tasks, memories: [])

        XCTAssertTrue(context.contains("ABC123"))  // Default thingsTaskId from mock
    }
}
