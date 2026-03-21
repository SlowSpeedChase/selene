import SeleneShared
import XCTest
@testable import SeleneChat

final class ContextBlocksE2ETests: XCTestCase {

    func testFullChunkAndRetrieveFlow() async {
        // Step 1: Chunk a note
        let chunkingService = ChunkingService()
        // Content must be long enough that mergeSmallSegments doesn't recombine.
        // Each section needs ~100+ tokens (400+ chars) to stay separate.
        let noteContent = """
        # Kitchen Renovation

        Need to get quotes from three contractors by Friday. Budget is $50k total. \
        Called Johnson Construction and they quoted $18k for cabinets and countertops. \
        Smith Builders said $22k but includes plumbing work. Still waiting on the third quote from ABC Remodeling. \
        The HOA requires written approval before starting any exterior work. \
        Need to submit the architectural drawings by end of month. \
        Insurance company wants photos of current kitchen condition before work begins. \
        Already got the building permit approved last Tuesday.

        # Timeline

        Start date is March 15. Expecting 6-8 weeks for completion. Need to order cabinets 4 weeks in advance. \
        Demolition phase will take approximately one week, followed by electrical and plumbing rough-in. \
        Cabinet installation scheduled for week three, with countertop templating immediately after. \
        Appliance delivery confirmed for week five. Final inspection and punch list in week six. \
        Need to arrange temporary kitchen setup in the garage during renovation. \
        Have to coordinate with the flooring contractor who is booked until mid-April.
        """

        let chunks = chunkingService.splitIntoChunks(noteContent)
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "Should split into at least 2 chunks for distinct topics")

        // Step 2: Create mock embeddings (simulate what nomic-embed-text returns)
        // Kitchen/contractor chunk gets an embedding pointing in direction A
        // Timeline chunk gets an embedding pointing in direction B
        let kitchenEmbedding: [Float] = [0.9, 0.1, 0.0]
        let timelineEmbedding: [Float] = [0.1, 0.9, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = chunks.enumerated().map { (i, content) in
            let chunk = NoteChunk.mock(
                id: Int64(i + 1),
                noteId: 1,
                chunkIndex: i,
                content: content,
                topic: i == 0 ? "contractor quotes" : "project timeline",
                tokenCount: chunkingService.estimateTokens(content)
            )
            let embedding = i == 0 ? kitchenEmbedding : timelineEmbedding
            return (chunk: chunk, embedding: embedding)
        }

        // Step 3: Query about contractors (should retrieve kitchen chunk)
        let retrievalService = ChunkRetrievalService()
        let contractorQuery: [Float] = [0.85, 0.15, 0.0]  // Similar to kitchen embedding

        let results = retrievalService.retrieveTopChunks(
            queryEmbedding: contractorQuery,
            candidates: candidates,
            limit: 1,
            minSimilarity: 0.3
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].chunk.content.contains("contractor") || results[0].chunk.content.contains("quotes"),
                      "Should retrieve the contractor/kitchen chunk, not the timeline chunk")

        // Step 4: Build prompt with retrieved chunks
        let builder = ThreadWorkspacePromptBuilder()
        let thread = Thread.mock(name: "Kitchen Renovation")

        let prompt = builder.buildInitialPromptWithChunks(
            thread: thread,
            retrievedChunks: results,
            tasks: []
        )

        XCTAssertTrue(prompt.contains("Kitchen Renovation"))
        XCTAssertTrue(prompt.contains("contractor") || prompt.contains("quotes"),
                      "Prompt should contain relevant chunk content")
    }
}
