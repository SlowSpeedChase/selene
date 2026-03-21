import SeleneShared
import XCTest
@testable import SeleneChat

final class ThreadWorkspacePromptRewriteTests: XCTestCase {

    func testSystemIdentityIsZen() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Morning Routine"),
            notes: [Note.mock()],
            tasks: []
        )

        // Should NOT contain old verbose instructions
        XCTAssertFalse(prompt.contains("Be concise but thorough"))
        XCTAssertFalse(prompt.contains("200 words"))

        // Should contain zen markers
        XCTAssertTrue(prompt.contains("Minimal. Precise. Kind."))
        XCTAssertTrue(prompt.contains("Every word earns its place") || prompt.contains("Never summarize the thread unless asked"))
    }

    func testWhatsNextPromptPresentsOptions() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildWhatsNextPrompt(
            thread: Thread.mock(name: "Morning Routine"),
            notes: [Note.mock()],
            tasks: [ThreadTask.mock()]
        )

        XCTAssertTrue(prompt.contains("2-3"))
        XCTAssertTrue(prompt.contains("trade-off") || prompt.contains("tradeoff") || prompt.contains("trade-offs") || prompt.contains("tradeoffs"))
    }

    func testPlanningPromptAsksQuestionsFirst() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildPlanningPrompt(
            thread: Thread.mock(name: "Career"),
            notes: [],
            tasks: [],
            userQuery: "help me figure this out"
        )

        XCTAssertTrue(prompt.contains("ask") || prompt.contains("Ask"))
        XCTAssertTrue(prompt.contains("question") || prompt.contains("clarif"))
    }

    func testContextBlockAwareness() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertTrue(prompt.contains("EMOTIONAL HISTORY"))
        XCTAssertTrue(prompt.contains("TASK HISTORY"))
    }
}
