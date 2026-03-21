import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkRetrievalIntegrationTests: XCTestCase {

    func testBuildPromptWithChunksIncludesTopicLabels() {
        let builder = ThreadWorkspacePromptBuilder()
        let thread = Thread.mock(name: "Project Planning")
        let chunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 1, content: "Need to schedule contractor meetings.", topic: "contractor scheduling"), 0.9),
            (NoteChunk.mock(id: 2, content: "Budget is approximately $50k.", topic: "budget overview"), 0.8),
        ]

        let prompt = builder.buildInitialPromptWithChunks(
            thread: thread,
            retrievedChunks: chunks,
            tasks: []
        )

        XCTAssertTrue(prompt.contains("contractor scheduling"))
        XCTAssertTrue(prompt.contains("budget overview"))
        XCTAssertTrue(prompt.contains("$50k"))
        XCTAssertTrue(prompt.contains("Project Planning"))
    }

    func testFollowUpPromptIncludesPinnedChunks() {
        let builder = ThreadWorkspacePromptBuilder()
        let thread = Thread.mock(name: "Project Planning")

        let pinnedChunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 1, content: "Original context from turn 1.", topic: "pinned context"), 0.0),
        ]
        let newChunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 2, content: "New relevant context.", topic: "new info"), 0.85),
        ]

        let prompt = builder.buildFollowUpPromptWithChunks(
            thread: thread,
            pinnedChunks: pinnedChunks,
            retrievedChunks: newChunks,
            tasks: [],
            conversationHistory: "User: Tell me about the budget\nAssistant: The budget is $50k.",
            currentQuery: "Break that into phases"
        )

        XCTAssertTrue(prompt.contains("pinned context"))
        XCTAssertTrue(prompt.contains("new info"))
        XCTAssertTrue(prompt.contains("Break that into phases"))
    }

    func testChunkPinningTracksReferencedChunks() {
        var pinnedChunkIds: Set<Int64> = []

        let turn1Chunks: [Int64] = [1, 2, 3]
        pinnedChunkIds.formUnion(turn1Chunks)

        let turn2Chunks: [Int64] = [2, 4]
        pinnedChunkIds.formUnion(turn2Chunks)

        XCTAssertEqual(pinnedChunkIds, [1, 2, 3, 4])
    }

    func testChunkContextDeduplicates() {
        let builder = ThreadWorkspacePromptBuilder()
        let thread = Thread.mock(name: "Dedup Test")

        // Same chunk ID appears in both pinned and retrieved
        let pinnedChunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 1, content: "Shared chunk content.", topic: "shared"), 0.9),
        ]
        let retrievedChunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 1, content: "Shared chunk content.", topic: "shared"), 0.85),
            (NoteChunk.mock(id: 2, content: "Unique chunk content.", topic: "unique"), 0.8),
        ]

        let prompt = builder.buildFollowUpPromptWithChunks(
            thread: thread,
            pinnedChunks: pinnedChunks,
            retrievedChunks: retrievedChunks,
            tasks: [],
            conversationHistory: "User: Hi\nAssistant: Hello.",
            currentQuery: "Tell me more"
        )

        // "Shared chunk content." should appear only once due to deduplication
        let occurrences = prompt.components(separatedBy: "Shared chunk content.").count - 1
        XCTAssertEqual(occurrences, 1, "Duplicate chunks should be deduplicated")
    }

    func testInitialPromptWithChunksIncludesThreadWhy() {
        let builder = ThreadWorkspacePromptBuilder()
        let thread = Thread.mock(name: "Home Renovation", why: "Because the kitchen is falling apart")
        let chunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 1, content: "Cabinet measurements.", topic: "cabinets"), 0.9),
        ]

        let prompt = builder.buildInitialPromptWithChunks(
            thread: thread,
            retrievedChunks: chunks,
            tasks: []
        )

        XCTAssertTrue(prompt.contains("Because the kitchen is falling apart"))
        XCTAssertTrue(prompt.contains("Home Renovation"))
    }

    func testDeepDiveTokenBudgetIs8000() {
        XCTAssertEqual(ThinkingPartnerQueryType.deepDive.tokenBudget, 8000)
    }
}
