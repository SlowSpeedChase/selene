import SeleneShared
import XCTest
@testable import SeleneChat

final class ActionServiceTests: XCTestCase {

    // MARK: - Test Setup

    private func makeTestAction(
        description: String = "Test action",
        energy: ActionExtractor.ExtractedAction.EnergyLevel = .medium,
        timeframe: ActionExtractor.ExtractedAction.Timeframe = .thisWeek
    ) -> ActionExtractor.ExtractedAction {
        ActionExtractor.ExtractedAction(
            description: description,
            energy: energy,
            timeframe: timeframe
        )
    }

    // MARK: - capture and getCapturedActions Tests

    func testCaptureActionStoresInMemory() async {
        let service = ActionService()
        let action = makeTestAction(description: "Review project proposal")

        await service.capture(action, threadName: "Project Planning")

        let captured = await service.getCapturedActions()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured[0].action.description, "Review project proposal")
        XCTAssertEqual(captured[0].threadName, "Project Planning")
    }

    func testCaptureMultipleActionsStoresAll() async {
        let service = ActionService()
        let action1 = makeTestAction(description: "First action")
        let action2 = makeTestAction(description: "Second action")

        await service.capture(action1, threadName: "Thread A")
        await service.capture(action2, threadName: "Thread B")

        let captured = await service.getCapturedActions()
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].action.description, "First action")
        XCTAssertEqual(captured[1].action.description, "Second action")
    }

    func testCapturedActionHasTimestamp() async {
        let service = ActionService()
        let action = makeTestAction()
        let beforeCapture = Date()

        await service.capture(action, threadName: "Test Thread")

        let captured = await service.getCapturedActions()
        XCTAssertEqual(captured.count, 1)
        XCTAssertGreaterThanOrEqual(captured[0].capturedAt, beforeCapture)
        XCTAssertLessThanOrEqual(captured[0].capturedAt, Date())
    }

    // MARK: - clearActions Tests

    func testClearActionsClearsMemory() async {
        let service = ActionService()
        let action = makeTestAction()

        await service.capture(action, threadName: "Test Thread")
        var captured = await service.getCapturedActions()
        XCTAssertEqual(captured.count, 1)

        await service.clearActions()

        captured = await service.getCapturedActions()
        XCTAssertTrue(captured.isEmpty)
    }

    func testClearActionsOnEmptyListDoesNotError() async {
        let service = ActionService()

        await service.clearActions()

        let captured = await service.getCapturedActions()
        XCTAssertTrue(captured.isEmpty)
    }

    // MARK: - buildThingsTask Tests

    func testBuildThingsTaskFromAction() {
        let service = ActionService()
        let action = makeTestAction(
            description: "Review the architecture document",
            energy: .high,
            timeframe: .today
        )

        let task = service.buildThingsTask(from: action, threadName: "Architecture Review")

        XCTAssertEqual(task.title, "Review the architecture document")
        XCTAssertTrue(task.notes.contains("From Selene thread: Architecture Review"))
        XCTAssertTrue(task.notes.contains("Energy: high"))
        XCTAssertEqual(task.tags, ["selene", "deep-dive"])
    }

    func testBuildThingsTaskTodayDeadline() {
        let service = ActionService()
        let action = makeTestAction(timeframe: .today)

        let task = service.buildThingsTask(from: action, threadName: "Test")

        XCTAssertNotNil(task.deadline)
        // Deadline should be today
        let calendar = Calendar.current
        XCTAssertTrue(calendar.isDateInToday(task.deadline!))
    }

    func testBuildThingsTaskThisWeekDeadline() {
        let service = ActionService()
        let action = makeTestAction(timeframe: .thisWeek)

        let task = service.buildThingsTask(from: action, threadName: "Test")

        XCTAssertNotNil(task.deadline)
        // Deadline should be approximately 7 days from now (allow for timing edge cases)
        let calendar = Calendar.current
        let daysDifference = calendar.dateComponents([.day], from: Date(), to: task.deadline!).day!
        // Allow for 6-7 days due to time component differences
        XCTAssertTrue(daysDifference >= 6 && daysDifference <= 7, "Expected 6-7 days, got \(daysDifference)")
    }

    func testBuildThingsTaskSomedayNoDeadline() {
        let service = ActionService()
        let action = makeTestAction(timeframe: .someday)

        let task = service.buildThingsTask(from: action, threadName: "Test")

        XCTAssertNil(task.deadline)
    }

    func testBuildThingsTaskListNameIsNil() {
        let service = ActionService()
        let action = makeTestAction()

        let task = service.buildThingsTask(from: action, threadName: "Test")

        XCTAssertNil(task.listName)
    }

    func testBuildThingsTaskNotesFormat() {
        let service = ActionService()
        let action = makeTestAction(energy: .low)

        let task = service.buildThingsTask(from: action, threadName: "My Thread")

        let expectedNotes = "From Selene thread: My Thread\nEnergy: low"
        XCTAssertEqual(task.notes, expectedNotes)
    }

    // MARK: - sendToThingsAndLinkThread Task Building

    func testBuildThingsTaskForThreadLinkIncludesThreadName() {
        let service = ActionService()
        let action = makeTestAction(
            description: "Set up test database",
            energy: .medium,
            timeframe: .thisWeek
        )

        let task = service.buildThingsTask(from: action, threadName: "Infrastructure")

        XCTAssertEqual(task.title, "Set up test database")
        XCTAssertTrue(task.notes.contains("Infrastructure"))
        XCTAssertTrue(task.tags.contains("selene"))
    }
}
