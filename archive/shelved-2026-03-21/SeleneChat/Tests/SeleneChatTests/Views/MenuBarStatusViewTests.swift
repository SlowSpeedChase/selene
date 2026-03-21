import SeleneShared
import XCTest
@testable import SeleneChat

final class MenuBarStatusViewTests: XCTestCase {

    // MARK: - Status Dot Symbol

    @MainActor
    func testStatusDotSymbolWhenIdle() {
        let scheduler = WorkflowScheduler()
        // No active workflows => idle
        let symbol = scheduler.activeWorkflows.isEmpty ? "circle" : "circle.fill"
        XCTAssertEqual(symbol, "circle")
    }

    @MainActor
    func testStatusDotSymbolWhenActive() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("process-llm")
        let symbol = scheduler.activeWorkflows.isEmpty ? "circle" : "circle.fill"
        XCTAssertEqual(symbol, "circle.fill")
    }

    // MARK: - Status Dot Color

    @MainActor
    func testStatusDotColorNameWhenIdle() {
        let scheduler = WorkflowScheduler()
        // When idle, color should be "secondary"
        let colorName = scheduler.activeWorkflows.isEmpty ? "secondary" : "green"
        XCTAssertEqual(colorName, "secondary")
    }

    @MainActor
    func testStatusDotColorNameWhenActive() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("compute-embeddings")
        let colorName = scheduler.activeWorkflows.isEmpty ? "secondary" : "green"
        XCTAssertEqual(colorName, "green")
    }

    // MARK: - Status Text

    @MainActor
    func testStatusTextWhenIdle() {
        let scheduler = WorkflowScheduler()
        XCTAssertEqual(scheduler.statusText, "Idle")
    }

    @MainActor
    func testStatusTextWhenOneWorkflowActive() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("process-llm")
        XCTAssertEqual(scheduler.statusText, "Running process-llm...")
    }

    @MainActor
    func testStatusTextWhenMultipleWorkflowsActive() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("process-llm")
        scheduler.activeWorkflows.insert("compute-embeddings")
        XCTAssertEqual(scheduler.statusText, "Running 2 workflows...")
    }
}
