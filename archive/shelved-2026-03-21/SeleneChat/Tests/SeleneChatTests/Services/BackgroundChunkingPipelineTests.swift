import SeleneShared
import XCTest
@testable import SeleneChat

@MainActor
final class BackgroundChunkingPipelineTests: XCTestCase {

    func testPipelinePublishesProgress() {
        let pipeline = BackgroundChunkingPipeline()

        XCTAssertEqual(pipeline.totalToProcess, 0)
        XCTAssertEqual(pipeline.processedCount, 0)
        XCTAssertFalse(pipeline.isProcessing)
    }

    func testChunkNoteProducesChunks() {
        let chunkingService = ChunkingService()

        let content = "First idea about project planning and scheduling.\n\nSecond idea about budget allocation and tracking."
        let chunks = chunkingService.splitIntoChunks(content)

        XCTAssertGreaterThanOrEqual(chunks.count, 1, "Should produce at least one chunk")
    }
}
