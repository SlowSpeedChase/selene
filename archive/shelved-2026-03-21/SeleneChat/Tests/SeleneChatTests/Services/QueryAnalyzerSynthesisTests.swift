import SeleneShared
import XCTest
@testable import SeleneChat

final class QueryAnalyzerSynthesisTests: XCTestCase {

    var analyzer: QueryAnalyzer!

    override func setUp() {
        super.setUp()
        analyzer = QueryAnalyzer()
    }

    override func tearDown() {
        analyzer = nil
        super.tearDown()
    }

    // MARK: - Synthesis Intent Detection Tests

    func testDetectsSynthesisIntent() {
        // Test various synthesis patterns
        let synthesisQueries = [
            "what should i focus on",
            "what should i work on",
            "help me prioritize",
            "what's most important",
            "whats most important",
            "where should i put my energy",
            "what needs my attention",
            "what deserves my focus",
            "prioritize my threads",
            "what's the priority",
            "whats the priority"
        ]

        for query in synthesisQueries {
            let result = analyzer.detectSynthesisIntent(query)
            XCTAssertTrue(result, "Expected synthesis intent for: \(query)")
        }
    }

    func testNonSynthesisQueriesReturnFalse() {
        // Queries that should NOT be detected as synthesis
        let nonSynthesisQueries = [
            "what's emerging",
            "show me my notes",
            "find notes about testing",
            "what patterns do I have",
            "show me the testing thread",
            "what did I write about architecture",
            "tell me about project journey thread",
            "dig into project planning",
            "explore the testing thread"
        ]

        for query in nonSynthesisQueries {
            let result = analyzer.detectSynthesisIntent(query)
            XCTAssertFalse(result, "Expected false for non-synthesis query: \(query)")
        }
    }

    func testSynthesisQueryTypeDetected() {
        // Test that analyze() returns .synthesis queryType
        let synthesisQueries = [
            "what should i focus on",
            "help me prioritize",
            "what's most important",
            "where should i put my energy",
            "what needs my attention"
        ]

        for query in synthesisQueries {
            let result = analyzer.analyze(query)
            XCTAssertEqual(
                result.queryType,
                .synthesis,
                "Expected .synthesis queryType for: \(query)"
            )
        }
    }

    func testSynthesisDetectionIsCaseInsensitive() {
        // Test that detection works regardless of case
        let testCases = [
            "What Should I Focus On",
            "WHAT SHOULD I FOCUS ON",
            "What's Most Important",
            "HELP ME PRIORITIZE",
            "What Needs My Attention"
        ]

        for query in testCases {
            let result = analyzer.detectSynthesisIntent(query)
            XCTAssertTrue(result, "Expected synthesis intent (case insensitive) for: \(query)")
        }
    }

    // MARK: - Edge Cases

    func testSynthesisInPartialSentence() {
        // Synthesis indicators within larger sentences
        let queries = [
            "hey, what should i focus on today?",
            "can you help me prioritize my work",
            "i'm feeling scattered, what needs my attention right now"
        ]

        for query in queries {
            let result = analyzer.detectSynthesisIntent(query)
            XCTAssertTrue(result, "Expected synthesis intent in sentence: \(query)")
        }
    }

    func testSynthesisTypeDescription() {
        // Verify the CustomStringConvertible implementation
        let result = analyzer.analyze("what should i focus on")
        XCTAssertEqual(result.queryType.description, "synthesis")
    }
}
