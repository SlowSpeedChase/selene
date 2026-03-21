import SeleneShared
import XCTest
@testable import SeleneChat

final class SilverCrystalIconTests: XCTestCase {

    // MARK: - CrystalIconState.isAnimating

    func testIdleIsNotAnimating() {
        let state = CrystalIconState.idle
        XCTAssertFalse(state.isAnimating)
    }

    func testProcessingIsAnimating() {
        let state = CrystalIconState.processing
        XCTAssertTrue(state.isAnimating)
    }

    func testErrorIsNotAnimating() {
        let state = CrystalIconState.error
        XCTAssertFalse(state.isAnimating)
    }

    // MARK: - CrystalIconState.showsErrorBadge

    func testIdleShowsNoErrorBadge() {
        let state = CrystalIconState.idle
        XCTAssertFalse(state.showsErrorBadge)
    }

    func testProcessingShowsNoErrorBadge() {
        let state = CrystalIconState.processing
        XCTAssertFalse(state.showsErrorBadge)
    }

    func testErrorShowsErrorBadge() {
        let state = CrystalIconState.error
        XCTAssertTrue(state.showsErrorBadge)
    }

    // MARK: - CrystalIconState.from()

    func testFromOllamaActiveReturnsProcessing() {
        let state = CrystalIconState.from(isOllamaActive: true, hasError: false)
        XCTAssertEqual(state, .processing)
    }

    func testFromHasErrorReturnsError() {
        let state = CrystalIconState.from(isOllamaActive: false, hasError: true)
        XCTAssertEqual(state, .error)
    }

    func testFromBothFalseReturnsIdle() {
        let state = CrystalIconState.from(isOllamaActive: false, hasError: false)
        XCTAssertEqual(state, .idle)
    }

    func testFromBothTrueReturnsProcessingPriority() {
        // Processing takes priority over error
        let state = CrystalIconState.from(isOllamaActive: true, hasError: true)
        XCTAssertEqual(state, .processing)
    }

    // MARK: - CrystalIconState Equatable

    func testEquatableSameStates() {
        XCTAssertEqual(CrystalIconState.idle, CrystalIconState.idle)
        XCTAssertEqual(CrystalIconState.processing, CrystalIconState.processing)
        XCTAssertEqual(CrystalIconState.error, CrystalIconState.error)
    }

    func testEquatableDifferentStates() {
        XCTAssertNotEqual(CrystalIconState.idle, CrystalIconState.processing)
        XCTAssertNotEqual(CrystalIconState.idle, CrystalIconState.error)
        XCTAssertNotEqual(CrystalIconState.processing, CrystalIconState.error)
    }
}
