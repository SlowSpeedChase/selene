import SeleneShared
import XCTest
@testable import SeleneChat

@MainActor
final class WorkflowSchedulerTests: XCTestCase {

    var scheduler: WorkflowScheduler!

    override func setUp() {
        super.setUp()
        scheduler = WorkflowScheduler()
    }

    override func tearDown() {
        scheduler.shutdown()
        scheduler = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialActiveWorkflowsIsEmpty() {
        XCTAssertTrue(scheduler.activeWorkflows.isEmpty, "activeWorkflows should start empty")
    }

    func testInitialIsOllamaActiveFalse() {
        XCTAssertFalse(scheduler.isOllamaActive, "isOllamaActive should be false when no workflows running")
    }

    func testInitialLastErrorIsNil() {
        XCTAssertNil(scheduler.lastError, "lastError should start as nil")
    }

    func testInitialIsEnabledFalse() {
        XCTAssertFalse(scheduler.isEnabled, "isEnabled should start as false")
    }

    // MARK: - isOllamaActive

    func testIsOllamaActiveWhenOllamaWorkflowRunning() {
        // "Process LLM" uses Ollama (usesOllama: true in ScheduledWorkflow.allWorkflows)
        scheduler.activeWorkflows.insert("Process LLM")
        XCTAssertTrue(scheduler.isOllamaActive, "isOllamaActive should be true when an Ollama workflow is running")
    }

    func testIsOllamaActiveWithMultipleOllamaWorkflows() {
        scheduler.activeWorkflows.insert("Process LLM")
        scheduler.activeWorkflows.insert("Extract Tasks")
        XCTAssertTrue(scheduler.isOllamaActive, "isOllamaActive should be true with multiple Ollama workflows")
    }

    func testIsOllamaActiveFalseWithNonOllamaWorkflow() {
        // "Selene Server" does not use Ollama (usesOllama: false)
        scheduler.activeWorkflows.insert("Selene Server")
        XCTAssertFalse(scheduler.isOllamaActive, "isOllamaActive should be false when only non-Ollama workflows running")
    }

    func testIsOllamaActiveFalseWithOnlyNonOllamaWorkflows() {
        scheduler.activeWorkflows.insert("Compute Relationships")
        scheduler.activeWorkflows.insert("Export Obsidian")
        scheduler.activeWorkflows.insert("Send Digest")
        XCTAssertFalse(scheduler.isOllamaActive, "isOllamaActive should be false with only non-Ollama workflows")
    }

    func testIsOllamaActiveTrueWithMixedWorkflows() {
        scheduler.activeWorkflows.insert("Compute Relationships")
        scheduler.activeWorkflows.insert("Process LLM")
        XCTAssertTrue(scheduler.isOllamaActive, "isOllamaActive should be true when at least one Ollama workflow is running")
    }

    // MARK: - statusText

    func testStatusTextIdleWhenEmpty() {
        XCTAssertEqual(scheduler.statusText, "Idle", "statusText should be 'Idle' when no workflows are active")
    }

    func testStatusTextSingleWorkflow() {
        scheduler.activeWorkflows.insert("Process LLM")
        XCTAssertEqual(
            scheduler.statusText,
            "Running Process LLM...",
            "statusText should show single workflow name"
        )
    }

    func testStatusTextMultipleWorkflows() {
        scheduler.activeWorkflows.insert("Process LLM")
        scheduler.activeWorkflows.insert("Extract Tasks")
        XCTAssertEqual(
            scheduler.statusText,
            "Running 2 workflows...",
            "statusText should show count for multiple workflows"
        )
    }

    func testStatusTextThreeWorkflows() {
        scheduler.activeWorkflows.insert("Process LLM")
        scheduler.activeWorkflows.insert("Extract Tasks")
        scheduler.activeWorkflows.insert("Compute Relationships")
        XCTAssertEqual(
            scheduler.statusText,
            "Running 3 workflows...",
            "statusText should show correct count for 3 workflows"
        )
    }

    // MARK: - enable / disable

    func testEnableSetsIsEnabled() {
        scheduler.enable()
        XCTAssertTrue(scheduler.isEnabled, "enable() should set isEnabled to true")
    }

    func testDisableClearsIsEnabled() {
        scheduler.enable()
        scheduler.disable()
        XCTAssertFalse(scheduler.isEnabled, "disable() should set isEnabled to false")
    }

    func testEnableAfterDisable() {
        scheduler.enable()
        scheduler.disable()
        scheduler.enable()
        XCTAssertTrue(scheduler.isEnabled, "enable() after disable() should set isEnabled to true again")
    }

    // MARK: - shutdown

    func testShutdownDisables() {
        scheduler.enable()
        scheduler.shutdown()
        XCTAssertFalse(scheduler.isEnabled, "shutdown() should disable the scheduler")
    }

    func testShutdownClearsActiveWorkflows() {
        scheduler.activeWorkflows.insert("Process LLM")
        scheduler.activeWorkflows.insert("Extract Tasks")
        scheduler.shutdown()
        XCTAssertTrue(scheduler.activeWorkflows.isEmpty, "shutdown() should clear active workflows")
    }

    // MARK: - WorkflowError

    func testWorkflowErrorCreation() {
        let error = WorkflowScheduler.WorkflowError(
            id: UUID(),
            workflowName: "Process LLM",
            message: "Exit code 1",
            occurredAt: Date()
        )
        XCTAssertEqual(error.workflowName, "Process LLM")
        XCTAssertEqual(error.message, "Exit code 1")
    }

    func testWorkflowErrorIdentifiable() {
        let errorId = UUID()
        let error = WorkflowScheduler.WorkflowError(
            id: errorId,
            workflowName: "Process LLM",
            message: "Failed",
            occurredAt: Date()
        )
        XCTAssertEqual(error.id, errorId, "WorkflowError should conform to Identifiable")
    }

    // MARK: - lastError Assignment

    func testLastErrorCanBeSet() {
        let error = WorkflowScheduler.WorkflowError(
            id: UUID(),
            workflowName: "Extract Tasks",
            message: "Timeout",
            occurredAt: Date()
        )
        scheduler.lastError = error
        XCTAssertNotNil(scheduler.lastError)
        XCTAssertEqual(scheduler.lastError?.workflowName, "Extract Tasks")
        XCTAssertEqual(scheduler.lastError?.message, "Timeout")
    }

    func testLastErrorCanBeCleared() {
        let error = WorkflowScheduler.WorkflowError(
            id: UUID(),
            workflowName: "Extract Tasks",
            message: "Timeout",
            occurredAt: Date()
        )
        scheduler.lastError = error
        scheduler.lastError = nil
        XCTAssertNil(scheduler.lastError)
    }
}
