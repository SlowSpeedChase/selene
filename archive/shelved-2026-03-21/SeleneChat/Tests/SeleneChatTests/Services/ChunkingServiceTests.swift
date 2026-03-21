import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkingServiceTests: XCTestCase {

    let service = ChunkingService()

    // MARK: - Paragraph Splitting

    func testSplitsOnDoubleNewlines() {
        // Each paragraph must be large enough (~100+ tokens each) that merging two would exceed maxTokens (256).
        // 100 tokens ~ 400 chars, so each paragraph is ~500 chars to prevent merging.
        let para1 = "First paragraph about planning. " + String(repeating: "We need to carefully plan every aspect of the project to ensure success and meet our deadlines on time. ", count: 5)
        let para2 = "Second paragraph about execution. " + String(repeating: "The execution phase requires careful coordination between all team members and stakeholders involved. ", count: 5)
        let para3 = "Third paragraph about review. " + String(repeating: "During the review phase we evaluate all outcomes and determine what improvements can be made going forward. ", count: 5)
        let content = "\(para1)\n\n\(para2)\n\n\(para3)"
        let chunks = service.splitIntoChunks(content)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks[0].contains("planning"))
        XCTAssertTrue(chunks[1].contains("execution"))
        XCTAssertTrue(chunks[2].contains("review"))
    }

    func testSplitsOnMarkdownHeaders() {
        // Each section must be large enough that merging two would exceed maxTokens (256 tokens).
        let planningDetails = String(repeating: "We need to carefully plan every aspect of the project to ensure success and meet our deadlines. ", count: 6)
        let executionDetails = String(repeating: "The execution phase requires careful coordination between all team members and stakeholders. ", count: 6)
        let content = """
        # Planning
        \(planningDetails)

        # Execution
        \(executionDetails)
        """
        let chunks = service.splitIntoChunks(content)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].contains("Planning"))
        XCTAssertTrue(chunks[1].contains("Execution"))
    }

    // MARK: - Merging Small Chunks

    func testMergesSmallChunks() {
        let content = "Short line one.\n\nShort line two.\n\nShort line three."
        let chunks = service.splitIntoChunks(content)

        XCTAssertLessThan(chunks.count, 3, "Small chunks should be merged together")
    }

    // MARK: - Splitting Large Chunks

    func testSplitsLargeChunksAtSentenceBoundaries() {
        let longParagraph = (1...20).map { "This is sentence number \($0) in a very long paragraph about various topics. " }.joined()
        let chunks = service.splitIntoChunks(longParagraph)

        XCTAssertGreaterThan(chunks.count, 1, "Long paragraph should be split into multiple chunks")
        for chunk in chunks {
            let tokenCount = service.estimateTokens(chunk)
            XCTAssertLessThanOrEqual(tokenCount, 300, "Each chunk should be under 300 tokens (with some tolerance)")
        }
    }

    // MARK: - Token Estimation

    func testEstimateTokens() {
        let text = "Hello world"
        let tokens = service.estimateTokens(text)
        XCTAssertEqual(tokens, 2) // 11 / 4 = 2
    }

    // MARK: - Edge Cases

    func testEmptyContentReturnsEmpty() {
        let chunks = service.splitIntoChunks("")
        XCTAssertTrue(chunks.isEmpty)
    }

    func testSingleShortParagraphReturnsOneChunk() {
        let content = "Just a single short note about something."
        let chunks = service.splitIntoChunks(content)
        XCTAssertEqual(chunks.count, 1)
    }

    func testWhitespaceOnlyReturnsEmpty() {
        let chunks = service.splitIntoChunks("   \n\n   \n\n   ")
        XCTAssertTrue(chunks.isEmpty)
    }
}
