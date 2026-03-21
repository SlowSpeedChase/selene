import SeleneShared
import XCTest
@testable import SeleneChat

final class DiscussionThreadTests: XCTestCase {

    func testThreadInitialization() {
        let thread = DiscussionThread(
            id: 1,
            rawNoteId: 42,
            threadType: .planning,
            prompt: "What's the first step?",
            status: .pending,
            createdAt: Date(),
            relatedConcepts: ["productivity", "goals"]
        )

        XCTAssertEqual(thread.id, 1)
        XCTAssertEqual(thread.rawNoteId, 42)
        XCTAssertEqual(thread.threadType, .planning)
        XCTAssertEqual(thread.status, .pending)
    }

    func testThreadTypeDisplayName() {
        XCTAssertEqual(DiscussionThread.ThreadType.planning.displayName, "Planning")
        XCTAssertEqual(DiscussionThread.ThreadType.followup.displayName, "Follow-up")
        XCTAssertEqual(DiscussionThread.ThreadType.question.displayName, "Question")
    }

    func testThreadStatusIcon() {
        XCTAssertEqual(DiscussionThread.Status.pending.icon, "clock")
        XCTAssertEqual(DiscussionThread.Status.active.icon, "play.circle")
        XCTAssertEqual(DiscussionThread.Status.completed.icon, "checkmark.circle")
    }
}
