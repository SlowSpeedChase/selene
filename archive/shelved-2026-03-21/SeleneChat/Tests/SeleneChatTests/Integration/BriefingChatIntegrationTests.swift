import SeleneShared
import XCTest
@testable import SeleneChat

final class BriefingChatIntegrationTests: XCTestCase {

    func testWhatChangedContextIsComplete() {
        let builder = BriefingContextBuilder()
        let note = Note.mock(id: 1, title: "Test Note", content: "Content about focus", concepts: ["focus", "productivity"])
        let thread = Thread.mock(id: 5, name: "Focus Systems", why: "Need better concentration", summary: "Deep work strategies")
        let related = [Note.mock(id: 2, title: "Related")]
        let tasks = [ThreadTask.mock(id: 1, threadId: 5, title: "Review notes")]

        let context = builder.buildWhatChangedContext(note: note, thread: thread, relatedNotes: related, tasks: tasks, memories: [])

        XCTAssertTrue(context.contains("Test Note"))
        XCTAssertTrue(context.contains("Content about focus"))
        XCTAssertTrue(context.contains("Focus Systems"))
        XCTAssertTrue(context.contains("Deep work strategies"))
        XCTAssertTrue(context.contains("Related"))
        XCTAssertTrue(context.contains("Review notes"))
    }

    func testNeedsAttentionContextIsComplete() {
        let builder = BriefingContextBuilder()
        let thread = Thread.mock(id: 5, name: "Stalled", why: "Important", summary: "Summary")
        let notes = [Note.mock(id: 1, title: "Last Note")]
        let tasks = [ThreadTask.mock(id: 1, threadId: 5, title: "Open Task")]

        let context = builder.buildNeedsAttentionContext(thread: thread, recentNotes: notes, tasks: tasks, memories: [])

        XCTAssertTrue(context.contains("Stalled"))
        XCTAssertTrue(context.contains("Important"))
        XCTAssertTrue(context.contains("Last Note"))
        XCTAssertTrue(context.contains("Open Task"))
    }

    func testConnectionContextIsComplete() {
        let builder = BriefingContextBuilder()
        let noteA = Note.mock(id: 1, title: "Note A", content: "Content A")
        let noteB = Note.mock(id: 2, title: "Note B", content: "Content B")
        let threadA = Thread.mock(id: 5, name: "Thread A")
        let threadB = Thread.mock(id: 8, name: "Thread B")

        let context = builder.buildConnectionContext(noteA: noteA, threadA: threadA, noteB: noteB, threadB: threadB, relatedToA: [], relatedToB: [], tasks: [], memories: [])

        XCTAssertTrue(context.contains("Note A"))
        XCTAssertTrue(context.contains("Note B"))
        XCTAssertTrue(context.contains("Thread A"))
        XCTAssertTrue(context.contains("Thread B"))
    }

    func testSystemPromptsAreDistinct() {
        let builder = BriefingContextBuilder()
        let p1 = builder.buildSystemPrompt(for: .whatChanged)
        let p2 = builder.buildSystemPrompt(for: .needsAttention)
        let p3 = builder.buildSystemPrompt(for: .connection)

        // All should mention Selene
        XCTAssertTrue(p1.contains("Selene"))
        XCTAssertTrue(p2.contains("Selene"))
        XCTAssertTrue(p3.contains("Selene"))

        // Each should have distinct guidance
        XCTAssertTrue(p1.contains("specific note"))
        XCTAssertTrue(p2.contains("stalled"))
        XCTAssertTrue(p3.contains("connection"))
    }
}
