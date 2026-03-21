import SeleneShared
import XCTest
@testable import SeleneChat

final class ActionExtractorTests: XCTestCase {

    // MARK: - extractActions Tests

    func testExtractsActionFromResponse() {
        let extractor = ActionExtractor()
        let response = """
        Based on your notes, here's what I suggest:

        [ACTION: Review the project proposal | ENERGY: high | TIMEFRAME: today]

        Let me know if you need more details.
        """

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].description, "Review the project proposal")
        XCTAssertEqual(actions[0].energy, .high)
        XCTAssertEqual(actions[0].timeframe, .today)
    }

    func testExtractsMultipleActions() {
        let extractor = ActionExtractor()
        let response = """
        I've identified two action items from your thread:

        [ACTION: Schedule meeting with team | ENERGY: low | TIMEFRAME: this-week]

        This should help get alignment.

        [ACTION: Draft architecture document | ENERGY: high | TIMEFRAME: today]

        These are the key next steps.
        """

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 2)

        XCTAssertEqual(actions[0].description, "Schedule meeting with team")
        XCTAssertEqual(actions[0].energy, .low)
        XCTAssertEqual(actions[0].timeframe, .thisWeek)

        XCTAssertEqual(actions[1].description, "Draft architecture document")
        XCTAssertEqual(actions[1].energy, .high)
        XCTAssertEqual(actions[1].timeframe, .today)
    }

    func testNoActionsReturnsEmptyArray() {
        let extractor = ActionExtractor()
        let response = """
        Here's a summary of your notes on the topic. There are several interesting
        patterns emerging, but no specific action items identified at this time.
        """

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 0)
        XCTAssertTrue(actions.isEmpty)
    }

    func testDefaultsEnergyToMediumForInvalidValue() {
        let extractor = ActionExtractor()
        let response = "[ACTION: Test task | ENERGY: extreme | TIMEFRAME: today]"

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].energy, .medium)
    }

    func testDefaultsTimeframeToSomedayForInvalidValue() {
        let extractor = ActionExtractor()
        let response = "[ACTION: Test task | ENERGY: high | TIMEFRAME: next-year]"

        let actions = extractor.extractActions(from: response)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions[0].timeframe, .someday)
    }

    // MARK: - removeActionMarkers Tests

    func testRemovesActionMarkersFromDisplay() {
        let extractor = ActionExtractor()
        let response = """
        Here's my analysis:

        [ACTION: Review the code | ENERGY: medium | TIMEFRAME: today]

        Based on the patterns I see, this would be helpful.
        """

        let cleaned = extractor.removeActionMarkers(from: response)

        XCTAssertFalse(cleaned.contains("[ACTION:"))
        XCTAssertFalse(cleaned.contains("ENERGY:"))
        XCTAssertFalse(cleaned.contains("TIMEFRAME:"))
        XCTAssertTrue(cleaned.contains("Here's my analysis:"))
        XCTAssertTrue(cleaned.contains("Based on the patterns I see"))
    }

    func testRemovesMultipleActionMarkers() {
        let extractor = ActionExtractor()
        let response = """
        [ACTION: First task | ENERGY: high | TIMEFRAME: today]
        Some text between.
        [ACTION: Second task | ENERGY: low | TIMEFRAME: someday]
        """

        let cleaned = extractor.removeActionMarkers(from: response)

        XCTAssertFalse(cleaned.contains("[ACTION:"))
        XCTAssertTrue(cleaned.contains("Some text between."))
    }

    func testRemoveMarkersTrimsWhitespace() {
        let extractor = ActionExtractor()
        let response = "   [ACTION: Task | ENERGY: low | TIMEFRAME: someday]   Content here   "

        let cleaned = extractor.removeActionMarkers(from: response)

        XCTAssertEqual(cleaned, "Content here")
    }
}
