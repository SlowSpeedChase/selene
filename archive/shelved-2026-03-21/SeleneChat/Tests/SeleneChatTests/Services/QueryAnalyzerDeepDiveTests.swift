import SeleneShared
import XCTest
@testable import SeleneChat

final class QueryAnalyzerDeepDiveTests: XCTestCase {

    var analyzer: QueryAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = QueryAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Deep Dive Intent Detection Tests

    func testDetectsDeepDiveIntent() {
        // Test various deep-dive patterns
        let testCases: [(query: String, expectedThreadName: String)] = [
            ("let's dig into project journey", "project journey"),
            ("lets dig into project journey", "project journey"),
            ("dig into event-driven architecture", "event-driven architecture"),
            ("explore the testing thread", "testing"),
            ("let's explore testing", "testing"),
            ("help me think through documentation", "documentation"),
            ("think through the api design thread", "api design"),
            ("let's unpack swift development", "swift development"),
            ("dive into project planning", "project planning"),
            ("deep dive into memory management", "memory management"),
            ("deep dive into the architecture thread", "architecture")
        ]

        for testCase in testCases {
            let intent = analyzer.detectDeepDiveIntent(testCase.query)
            XCTAssertNotNil(intent, "Expected deep-dive intent for: \(testCase.query)")
            XCTAssertEqual(
                intent?.threadName.lowercased(),
                testCase.expectedThreadName.lowercased(),
                "Expected thread name '\(testCase.expectedThreadName)' for query: \(testCase.query)"
            )
        }
    }

    func testNonDeepDiveQueriesReturnNil() {
        // Queries that should NOT be detected as deep-dive
        let nonDeepDiveQueries = [
            "what's emerging",
            "show me my notes",
            "find notes about testing",
            "what patterns do I have",
            "show me the testing thread",
            "what did I write about architecture",
            "tell me about project journey thread",
            // Conversational messages containing broad words should NOT trigger
            "I want to explore new ideas with you",
            "can you help me think through what happened today",
            "let me unpack my feelings about the project",
            "I need to explore why I feel this way about work"
        ]

        for query in nonDeepDiveQueries {
            let intent = analyzer.detectDeepDiveIntent(query)
            XCTAssertNil(intent, "Expected nil for non-deep-dive query: \(query)")
        }
    }

    func testDeepDiveQueryTypeDetected() {
        // Test that analyze() returns .deepDive queryType
        let deepDiveQueries = [
            "let's dig into project journey",
            "let's explore the testing thread",
            "help me think through documentation",
            "dive into architecture",
            "deep dive into memory management"
        ]

        for query in deepDiveQueries {
            let result = analyzer.analyze(query)
            XCTAssertEqual(
                result.queryType,
                .deepDive,
                "Expected .deepDive queryType for: \(query)"
            )
        }
    }

    // MARK: - Edge Cases

    func testDeepDiveIntentWithMixedCase() {
        let intent = analyzer.detectDeepDiveIntent("Let's Dig Into PROJECT JOURNEY")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.threadName.lowercased(), "project journey")
    }

    func testDeepDiveIntentStripsLeadingThe() {
        let intent = analyzer.detectDeepDiveIntent("explore the testing")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.threadName, "testing")
    }

    func testDeepDiveIntentStripsTrailingThread() {
        let intent = analyzer.detectDeepDiveIntent("dig into architecture thread")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.threadName, "architecture")
    }

    func testDeepDiveIntentStripsLeadingTheAndTrailingThread() {
        let intent = analyzer.detectDeepDiveIntent("explore the architecture thread")
        XCTAssertNotNil(intent)
        XCTAssertEqual(intent?.threadName, "architecture")
    }
}
