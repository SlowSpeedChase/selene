import XCTest
import SeleneShared

final class PlanningIntentDetectionTests: XCTestCase {
    let builder = ThreadWorkspacePromptBuilder()

    func testWhatsNextPatterns() {
        let queries = [
            "what's next", "what should I focus on", "what needs my attention",
            "what's most important", "what am I missing", "what's stalled"
        ]
        for query in queries {
            XCTAssertTrue(builder.isWhatsNextQuery(query), "Should detect: '\(query)'")
        }
    }

    func testPlanningPatterns() {
        let queries = [
            "help me think through this", "I'm stuck", "I don't know where to start",
            "what would you recommend", "talk me through this", "I'm overwhelmed",
            "I keep putting this off", "why am I avoiding this", "break this into pieces",
            "what's the simplest first step", "how do I even begin"
        ]
        for query in queries {
            XCTAssertTrue(builder.isPlanningQuery(query), "Should detect: '\(query)'")
        }
    }

    func testNonPlanningQueriesNotDetected() {
        let queries = [
            "show me notes about cooking", "when did I write about travel",
            "what's the weather"
        ]
        for query in queries {
            XCTAssertFalse(builder.isPlanningQuery(query), "Should NOT detect: '\(query)'")
        }
    }
}
