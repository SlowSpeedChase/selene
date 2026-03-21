import SeleneShared
import XCTest

final class ThreadWorkspaceRetrievalTests: XCTestCase {

    // MARK: - Context Block Formatting

    func testContextBlocksIncludeThreadState() {
        let block = ContextBlock(
            type: .threadState,
            content: "'Morning Routine' \u{2014} active, 8 notes, 2 open tasks, last activity 3d ago, momentum 0.7"
        )
        XCTAssertTrue(block.formatted.contains("[THREAD STATE]"))
        XCTAssertTrue(block.formatted.contains("Morning Routine"))
    }

    func testContextBlocksIncludeEmotionalHistory() {
        let block = ContextBlock(
            type: .emotionalHistory,
            content: "Felt overwhelmed by too many open threads",
            sourceDate: Date(),
            sourceTitle: "Weekly reflection"
        )
        XCTAssertTrue(block.formatted.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(block.formatted.contains("overwhelmed"))
        XCTAssertTrue(block.formatted.contains("Weekly reflection"))
    }

    func testContextBlocksIncludeTaskHistory() {
        let block = ContextBlock(
            type: .taskHistory,
            content: "Set up CI (done, 3d); Write docs (abandoned, 14d)"
        )
        XCTAssertTrue(block.formatted.contains("[TASK HISTORY]"))
        XCTAssertTrue(block.formatted.contains("Set up CI"))
        XCTAssertTrue(block.formatted.contains("abandoned"))
    }

    func testContextBlocksIncludeSentimentTrend() {
        let block = ContextBlock(
            type: .sentimentTrend,
            content: "This week (12 notes): 60% positive, 30% neutral, 10% negative"
        )
        XCTAssertTrue(block.formatted.contains("[EMOTIONAL TREND]"))
        XCTAssertTrue(block.formatted.contains("60% positive"))
    }

    // MARK: - Retrieved Context Formatting

    func testContextualSectionWithThreadState() {
        let blocks = [
            ContextBlock(type: .threadState, content: "'Health' \u{2014} active, 5 notes"),
            ContextBlock(
                type: .emotionalHistory,
                content: "Felt anxious about doctor visit",
                sourceDate: Date(),
                sourceTitle: "Health anxiety"
            ),
        ]
        let context = RetrievedContext(blocks: blocks)
        let section = "\n\n## Context from your history:\n\(context.formatted())\n"

        XCTAssertTrue(section.contains("[THREAD STATE]"))
        XCTAssertTrue(section.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(section.contains("## Context from your history:"))
    }

    func testRetrievedContextFormattedJoinsBlocks() {
        let blocks = [
            ContextBlock(type: .threadState, content: "Thread A"),
            ContextBlock(type: .taskHistory, content: "Task B (done, 2d)"),
            ContextBlock(type: .sentimentTrend, content: "Mostly positive"),
        ]
        let context = RetrievedContext(blocks: blocks)
        let formatted = context.formatted()

        // All blocks should be present, joined by newlines
        let lines = formatted.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].contains("[THREAD STATE]"))
        XCTAssertTrue(lines[1].contains("[TASK HISTORY]"))
        XCTAssertTrue(lines[2].contains("[EMOTIONAL TREND]"))
    }

    func testEmptyRetrievedContextFormatsAsEmptyString() {
        let context = RetrievedContext(blocks: [])
        XCTAssertTrue(context.formatted().isEmpty)
        XCTAssertEqual(context.estimatedTokens, 0)
    }

    // MARK: - Token Estimation

    func testEstimatedTokensApproximatesFourCharsPerToken() {
        let block = ContextBlock(
            type: .threadState,
            content: String(repeating: "abcd", count: 100) // 400 chars of content
        )
        let context = RetrievedContext(blocks: [block])
        // Formatted string includes the label prefix, so tokens > 100
        XCTAssertGreaterThan(context.estimatedTokens, 100)
        XCTAssertLessThan(context.estimatedTokens, 200)
    }
}
