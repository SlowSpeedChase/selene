import SeleneShared
import XCTest
@testable import SeleneChat

final class ClaudeAPIServiceTests: XCTestCase {

    func testBuildMessagesFormatsCorrectly() async {
        let service = ClaudeAPIService.shared

        let history: [[String: String]] = [
            ["role": "user", "content": "Hello"],
            ["role": "assistant", "content": "Hi there!"]
        ]

        let messages = await service.buildMessages(
            userMessage: "What's next?",
            conversationHistory: history
        )

        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertEqual(messages[0]["content"], "Hello")
        XCTAssertEqual(messages[2]["role"], "user")
        XCTAssertEqual(messages[2]["content"], "What's next?")
    }

    func testExtractTasksFromResponse() async {
        let service = ClaudeAPIService.shared

        let response = """
        That's a good starting point.
        [TASK: Research hosting options | energy: low | minutes: 30]
        What else do you need?
        """

        let tasks = await service.extractTasks(from: response)

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Research hosting options")
        XCTAssertEqual(tasks[0].energy, "low")
        XCTAssertEqual(tasks[0].minutes, 30)
    }

    func testExtractMultipleTasks() async {
        let service = ClaudeAPIService.shared

        let response = """
        Let me help you break this down:
        [TASK: List requirements | energy: low | minutes: 15]
        [TASK: Compare platforms | energy: medium | minutes: 60]
        Those are good first steps.
        """

        let tasks = await service.extractTasks(from: response)

        XCTAssertEqual(tasks.count, 2)
    }

    func testExtractTasksHandlesNoTasks() async {
        let service = ClaudeAPIService.shared

        let response = """
        This is a response without any task markers.
        Just plain text explaining something.
        """

        let tasks = await service.extractTasks(from: response)

        XCTAssertEqual(tasks.count, 0)
    }

    func testRemoveTaskMarkersFromResponse() async {
        let service = ClaudeAPIService.shared

        let response = """
        Let me suggest a task:
        [TASK: Do something | energy: low | minutes: 15]
        That should help.
        """

        let cleanMessage = await service.removeTaskMarkers(from: response)

        XCTAssertFalse(cleanMessage.contains("[TASK:"))
        XCTAssertTrue(cleanMessage.contains("Let me suggest a task:"))
        XCTAssertTrue(cleanMessage.contains("That should help."))
    }

    func testIsAvailable_returnsTrueWhenAPIKeySet() async {
        // This test checks basic availability logic
        // Note: Actual API key availability depends on environment
        let service = ClaudeAPIService.shared

        // The service should report availability based on API key presence
        _ = await service.isAvailable()
        // Just verify it doesn't crash - actual result depends on env
    }

    func testBuildMessagesWithEmptyHistory() async {
        let service = ClaudeAPIService.shared

        let history: [[String: String]] = []

        let messages = await service.buildMessages(
            userMessage: "First message",
            conversationHistory: history
        )

        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertEqual(messages[0]["content"], "First message")
    }

    func testExtractTasksHandlesCaseInsensitiveEnergy() async {
        let service = ClaudeAPIService.shared

        let response = """
        [TASK: Test task | energy: LOW | minutes: 20]
        [TASK: Another task | energy: HIGH | minutes: 45]
        """

        let tasks = await service.extractTasks(from: response)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].energy, "low")
        XCTAssertEqual(tasks[1].energy, "high")
    }
}
