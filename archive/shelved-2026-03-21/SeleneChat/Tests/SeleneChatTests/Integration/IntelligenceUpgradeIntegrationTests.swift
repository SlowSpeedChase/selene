import XCTest
import SeleneShared

final class IntelligenceUpgradeIntegrationTests: XCTestCase {

    func testFullPromptAssemblyContainsAllSections() {
        // Simulate what ChatViewModel would assemble
        let systemPrompt = """
        You are Selene. Minimal. Precise. Kind.
        RULES:
        - Never summarize unless asked. Engage.
        """

        let contextualBlocks = RetrievedContext(blocks: [
            ContextBlock(type: .emotionalHistory, content: "Felt frustrated about early mornings",
                         sourceDate: Date(), sourceTitle: "Morning frustration"),
            ContextBlock(type: .taskHistory, content: "wake-up-early (abandoned, 12d)"),
            ContextBlock(type: .sentimentTrend, content: "This week (8 notes): frustrated 3x"),
        ])

        let noteContext = "--- Morning Thoughts ---\nContent about morning routines..."

        let fullPrompt = """
        \(systemPrompt)

        ## Context from your history:
        \(contextualBlocks.formatted())

        Notes:
        \(noteContext)

        Question: help me with morning routines
        """

        // Verify all sections present
        XCTAssertTrue(fullPrompt.contains("Selene"))
        XCTAssertTrue(fullPrompt.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(fullPrompt.contains("[TASK HISTORY"))
        XCTAssertTrue(fullPrompt.contains("[EMOTIONAL TREND"))
        XCTAssertTrue(fullPrompt.contains("Morning Thoughts"))
        XCTAssertTrue(fullPrompt.contains("help me with morning routines"))

        // Verify order: system -> context -> notes -> question
        let systemRange = fullPrompt.range(of: "Selene")!
        let contextRange = fullPrompt.range(of: "[EMOTIONAL HISTORY")!
        let notesRange = fullPrompt.range(of: "Morning Thoughts")!
        let questionRange = fullPrompt.range(of: "help me with morning routines")!

        XCTAssertTrue(systemRange.lowerBound < contextRange.lowerBound)
        XCTAssertTrue(contextRange.lowerBound < notesRange.lowerBound)
        XCTAssertTrue(notesRange.lowerBound < questionRange.lowerBound)
    }

    func testContextBlockFormattingIncludesLabelsAndDates() {
        let date = Date()
        let block = ContextBlock(
            type: .emotionalHistory,
            content: "Feeling stuck on project priorities",
            sourceDate: date,
            sourceTitle: "Priority confusion"
        )

        let formatted = block.formatted
        XCTAssertTrue(formatted.contains("[EMOTIONAL HISTORY"))
        XCTAssertTrue(formatted.contains("Priority confusion"))
        XCTAssertTrue(formatted.contains("Feeling stuck"))
    }

    func testRetrievedContextTokenEstimation() {
        let blocks = [
            ContextBlock(type: .emotionalHistory, content: "Short content"),
            ContextBlock(type: .taskHistory, content: "Another block of content here"),
        ]
        let context = RetrievedContext(blocks: blocks)

        XCTAssertGreaterThan(context.estimatedTokens, 0)
        // Token estimate is chars / 4
        let expectedMinTokens = context.formatted().count / 4
        XCTAssertEqual(context.estimatedTokens, expectedMinTokens)
    }
}
