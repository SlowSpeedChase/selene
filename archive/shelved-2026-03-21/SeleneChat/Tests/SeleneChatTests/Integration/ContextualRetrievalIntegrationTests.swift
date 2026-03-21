import XCTest
import SeleneShared

final class ContextualRetrievalIntegrationTests: XCTestCase {

    func testRetrievedContextFormatsAsLabeledBlocks() {
        let blocks = [
            ContextBlock(type: .emotionalHistory, content: "Felt frustrated about morning routines",
                         sourceDate: Date(), sourceTitle: "Morning struggle"),
            ContextBlock(type: .taskHistory, content: "wake-up-early (abandoned, 12d); buy-alarm (done, 3d)"),
            ContextBlock(type: .sentimentTrend, content: "This week (8 notes): frustrated 3x, anxious 2x"),
        ]
        let context = RetrievedContext(blocks: blocks)
        let formatted = context.formatted()

        XCTAssertTrue(formatted.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(formatted.contains("[TASK HISTORY"))
        XCTAssertTrue(formatted.contains("[EMOTIONAL TREND"))
        XCTAssertTrue(formatted.contains("frustrated"))
    }

    func testContextualSectionAssembly() {
        let blocks = [
            ContextBlock(type: .emotionalHistory, content: "Test content"),
        ]
        let context = RetrievedContext(blocks: blocks)

        // Simulate what ChatViewModel does
        let contextualSection = context.blocks.isEmpty ? "" : """

        ## Context from your history:
        \(context.formatted())

        """

        XCTAssertTrue(contextualSection.contains("## Context from your history:"))
        XCTAssertTrue(contextualSection.contains("[EMOTIONAL HISTORY"))
    }

    func testEmptyContextProducesEmptySection() {
        let context = RetrievedContext(blocks: [])
        let contextualSection = context.blocks.isEmpty ? "" : "## Context:\n\(context.formatted())"
        XCTAssertEqual(contextualSection, "")
    }
}
