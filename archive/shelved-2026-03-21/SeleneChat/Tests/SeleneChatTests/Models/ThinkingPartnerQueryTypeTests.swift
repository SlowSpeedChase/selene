import SeleneShared
import XCTest
@testable import SeleneChat

final class ThinkingPartnerQueryTypeTests: XCTestCase {

    func testQueryTypeRawValues() {
        XCTAssertEqual(ThinkingPartnerQueryType.briefing.rawValue, "briefing")
        XCTAssertEqual(ThinkingPartnerQueryType.synthesis.rawValue, "synthesis")
        XCTAssertEqual(ThinkingPartnerQueryType.deepDive.rawValue, "deepDive")
    }

    func testQueryTypeTokenBudgets() {
        XCTAssertEqual(ThinkingPartnerQueryType.briefing.tokenBudget, 1500)
        XCTAssertEqual(ThinkingPartnerQueryType.synthesis.tokenBudget, 2000)
        XCTAssertEqual(ThinkingPartnerQueryType.deepDive.tokenBudget, 8000)
    }
}
