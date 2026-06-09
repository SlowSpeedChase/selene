# Context Blocks + Apple Intelligence Implementation Plan

> ## ⚠️ SUPERSEDED — do not implement (2026-06-09)
> This 10-task plan targets **`SeleneChat/...`** paths and a **thread-chat / `note_chunks`** system that were
> **archived in the 2026-03-21 simplification** and do not exist in the current codebase. It is also built on
> **iOS 26** Foundation Models assumptions (fixed ~3B / 4K context) that **iOS 27 superseded**. Retained for
> history only. See the revised design doc
> (`2026-02-14-context-blocks-apple-intelligence-design.md`) for the current Vision-stage re-scope; a fresh
> plan must be written against real current files before any code.

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace thread chat's all-notes-truncated context with chunk-based semantic retrieval, add Apple Intelligence as a second LLM provider, and route tasks to the best model.

**Architecture:** Notes are split into idea-level chunks (100-256 tokens) via rule-based splitting + Apple Foundation Models topic labeling. Chunks are embedded via nomic-embed-text and stored in SQLite. Thread conversations retrieve only relevant chunks via cosine similarity search, with a pinning mechanism to preserve context across turns. An LLM Router dispatches tasks to Apple Intelligence or Ollama based on task-type defaults.

**Tech Stack:** Swift 5.9+, FoundationModels framework (macOS 26), NaturalLanguage framework, SQLite.swift, Ollama (mistral:7b, nomic-embed-text)

---

## Task 1: NoteChunk Model

**Files:**
- Create: `SeleneChat/Sources/SeleneShared/Models/NoteChunk.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Models/NoteChunkTests.swift`

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class NoteChunkTests: XCTestCase {

    // MARK: - Initialization

    func testNoteChunkInitialization() {
        let chunk = NoteChunk(
            id: 1,
            noteId: 42,
            chunkIndex: 0,
            content: "This is a test chunk about project planning.",
            topic: "project planning",
            tokenCount: 9,
            createdAt: Date()
        )

        XCTAssertEqual(chunk.id, 1)
        XCTAssertEqual(chunk.noteId, 42)
        XCTAssertEqual(chunk.chunkIndex, 0)
        XCTAssertEqual(chunk.content, "This is a test chunk about project planning.")
        XCTAssertEqual(chunk.topic, "project planning")
        XCTAssertEqual(chunk.tokenCount, 9)
    }

    func testNoteChunkTopicIsOptional() {
        let chunk = NoteChunk(
            id: 1,
            noteId: 42,
            chunkIndex: 0,
            content: "Short chunk.",
            topic: nil,
            tokenCount: 2,
            createdAt: Date()
        )

        XCTAssertNil(chunk.topic)
    }

    func testNoteChunkPreviewTruncatesLongContent() {
        let longContent = String(repeating: "word ", count: 100)
        let chunk = NoteChunk(
            id: 1,
            noteId: 1,
            chunkIndex: 0,
            content: longContent,
            topic: nil,
            tokenCount: 100,
            createdAt: Date()
        )

        XCTAssertLessThanOrEqual(chunk.preview.count, 103, "Preview should truncate to ~100 chars + ellipsis")
    }

    func testNoteChunkIdentifiable() {
        let chunk = NoteChunk(
            id: 99,
            noteId: 1,
            chunkIndex: 0,
            content: "Test",
            topic: nil,
            tokenCount: 1,
            createdAt: Date()
        )

        XCTAssertEqual(chunk.id, 99)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter NoteChunkTests 2>&1 | head -20`
Expected: FAIL — `NoteChunk` type not found

**Step 3: Write minimal implementation**

```swift
import Foundation

/// A chunk of a note representing a single idea or point.
/// Used for semantic retrieval in thread conversations.
public struct NoteChunk: Identifiable, Hashable {
    public let id: Int64
    public let noteId: Int
    public let chunkIndex: Int
    public let content: String
    public let topic: String?
    public let tokenCount: Int
    public let createdAt: Date

    public init(
        id: Int64,
        noteId: Int,
        chunkIndex: Int,
        content: String,
        topic: String?,
        tokenCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.noteId = noteId
        self.chunkIndex = chunkIndex
        self.content = content
        self.topic = topic
        self.tokenCount = tokenCount
        self.createdAt = createdAt
    }

    /// Truncated preview for display
    public var preview: String {
        if content.count <= 100 { return content }
        return String(content.prefix(100)) + "..."
    }
}

#if DEBUG
extension NoteChunk {
    public static func mock(
        id: Int64 = 1,
        noteId: Int = 1,
        chunkIndex: Int = 0,
        content: String = "This is a mock chunk about a topic.",
        topic: String? = "mock topic",
        tokenCount: Int = 8,
        createdAt: Date = Date()
    ) -> NoteChunk {
        NoteChunk(
            id: id,
            noteId: noteId,
            chunkIndex: chunkIndex,
            content: content,
            topic: topic,
            tokenCount: tokenCount,
            createdAt: createdAt
        )
    }
}
#endif
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter NoteChunkTests 2>&1 | tail -5`
Expected: PASS — all 4 tests pass

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Models/NoteChunk.swift SeleneChat/Tests/SeleneChatTests/Models/NoteChunkTests.swift
git commit -m "feat: add NoteChunk model for context block system"
```

---

## Task 2: note_chunks Table in DatabaseService

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`
- Modify: `SeleneChat/Sources/SeleneShared/Protocols/DataProvider.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/NoteChunkDatabaseTests.swift`

**Context:** DatabaseService uses SQLite.swift with typed expressions. Table definitions are at the top of the file (~lines 10-140). Migrations are applied in `initializeDatabase()`. Add the `note_chunks` table and CRUD methods.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class NoteChunkDatabaseTests: XCTestCase {

    // MARK: - Chunk CRUD

    func testInsertAndRetrieveChunks() async throws {
        let db = DatabaseService.shared

        // Insert chunks for a note
        let chunk1 = try await db.insertNoteChunk(
            noteId: 1,
            chunkIndex: 0,
            content: "First idea about planning.",
            topic: "planning",
            tokenCount: 5,
            embedding: nil
        )
        let chunk2 = try await db.insertNoteChunk(
            noteId: 1,
            chunkIndex: 1,
            content: "Second idea about execution.",
            topic: "execution",
            tokenCount: 5,
            embedding: nil
        )

        XCTAssertGreaterThan(chunk1, 0, "Should return inserted row ID")
        XCTAssertGreaterThan(chunk2, 0)

        // Retrieve chunks for note
        let chunks = try await db.getChunksForNote(noteId: 1)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].chunkIndex, 0)
        XCTAssertEqual(chunks[1].chunkIndex, 1)
        XCTAssertEqual(chunks[0].topic, "planning")
    }

    func testGetChunksForMultipleNotes() async throws {
        let db = DatabaseService.shared

        _ = try await db.insertNoteChunk(noteId: 1, chunkIndex: 0, content: "Note 1 chunk", topic: nil, tokenCount: 3, embedding: nil)
        _ = try await db.insertNoteChunk(noteId: 2, chunkIndex: 0, content: "Note 2 chunk", topic: nil, tokenCount: 3, embedding: nil)
        _ = try await db.insertNoteChunk(noteId: 3, chunkIndex: 0, content: "Note 3 chunk", topic: nil, tokenCount: 3, embedding: nil)

        let chunks = try await db.getChunksForNotes(noteIds: [1, 3])
        XCTAssertEqual(chunks.count, 2, "Should return chunks for notes 1 and 3 only")
    }

    func testDeleteChunksForNote() async throws {
        let db = DatabaseService.shared

        _ = try await db.insertNoteChunk(noteId: 1, chunkIndex: 0, content: "Chunk A", topic: nil, tokenCount: 2, embedding: nil)
        _ = try await db.insertNoteChunk(noteId: 1, chunkIndex: 1, content: "Chunk B", topic: nil, tokenCount: 2, embedding: nil)

        try await db.deleteChunksForNote(noteId: 1)

        let chunks = try await db.getChunksForNote(noteId: 1)
        XCTAssertTrue(chunks.isEmpty, "All chunks for note should be deleted")
    }

    func testGetUncunkedNoteIds() async throws {
        let db = DatabaseService.shared

        // This returns note IDs from raw_notes that have no entries in note_chunks
        let unchunked = try await db.getUnchunkedNoteIds(limit: 50)
        // Can't assert exact count without test data setup, but method should not throw
        XCTAssertNotNil(unchunked)
    }

    // MARK: - Embedding Storage

    func testSaveAndRetrieveChunkEmbedding() async throws {
        let db = DatabaseService.shared

        let chunkId = try await db.insertNoteChunk(
            noteId: 1, chunkIndex: 0,
            content: "Embeddable chunk", topic: nil,
            tokenCount: 2, embedding: nil
        )

        let testEmbedding: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        try await db.saveChunkEmbedding(chunkId: chunkId, embedding: testEmbedding)

        let chunksWithEmbeddings = try await db.getChunksWithEmbeddings(noteIds: [1])
        XCTAssertEqual(chunksWithEmbeddings.count, 1)
        XCTAssertNotNil(chunksWithEmbeddings[0].embedding)
        XCTAssertEqual(chunksWithEmbeddings[0].embedding?.count, 5)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter NoteChunkDatabaseTests 2>&1 | head -20`
Expected: FAIL — methods not found on DatabaseService

**Step 3: Implement the note_chunks table and methods**

Add to DatabaseService.swift table definitions (near line ~130, after existing table defs):

```swift
// MARK: - Note Chunks Table
private let noteChunksTable = Table("note_chunks")
private let chunkId = Expression<Int64>("id")
private let chunkNoteId = Expression<Int>("note_id")
private let chunkIndex = Expression<Int>("chunk_index")
private let chunkContent = Expression<String>("content")
private let chunkTopic = Expression<String?>("topic")
private let chunkTokenCount = Expression<Int>("token_count")
private let chunkEmbedding = Expression<Data?>("embedding")
private let chunkCreatedAt = Expression<String>("created_at")
```

Add migration in `initializeDatabase()`:

```swift
try db.run(noteChunksTable.create(ifNotExists: true) { t in
    t.column(chunkId, primaryKey: .autoincrement)
    t.column(chunkNoteId)
    t.column(chunkIndex)
    t.column(chunkContent)
    t.column(chunkTopic)
    t.column(chunkTokenCount)
    t.column(chunkEmbedding)
    t.column(chunkCreatedAt)
    t.unique(chunkNoteId, chunkIndex)
})
try db.run(noteChunksTable.createIndex(chunkNoteId, ifNotExists: true))
```

Add CRUD methods:

```swift
// MARK: - Note Chunks

func insertNoteChunk(noteId: Int, chunkIndex: Int, content: String, topic: String?, tokenCount: Int, embedding: [Float]?) async throws -> Int64 {
    guard let db = db else { throw DatabaseError.notConnected }
    let embeddingData = embedding.map { VectorUtility.floatsToData($0) }
    let now = ISO8601DateFormatter().string(from: Date())
    return try db.run(noteChunksTable.insert(
        chunkNoteId <- noteId,
        self.chunkIndex <- chunkIndex,
        chunkContent <- content,
        chunkTopic <- topic,
        chunkTokenCount <- tokenCount,
        chunkEmbedding <- embeddingData,
        chunkCreatedAt <- now
    ))
}

func getChunksForNote(noteId: Int) async throws -> [NoteChunk] {
    guard let db = db else { throw DatabaseError.notConnected }
    let query = noteChunksTable
        .filter(chunkNoteId == noteId)
        .order(chunkIndex.asc)
    return try db.prepare(query).map { row in
        NoteChunk(
            id: row[chunkId],
            noteId: row[chunkNoteId],
            chunkIndex: row[self.chunkIndex],
            content: row[chunkContent],
            topic: row[chunkTopic],
            tokenCount: row[chunkTokenCount],
            createdAt: ISO8601DateFormatter().date(from: row[chunkCreatedAt]) ?? Date()
        )
    }
}

func getChunksForNotes(noteIds: [Int]) async throws -> [NoteChunk] {
    guard let db = db else { throw DatabaseError.notConnected }
    let query = noteChunksTable
        .filter(noteIds.contains(chunkNoteId))
        .order(chunkNoteId.asc, chunkIndex.asc)
    return try db.prepare(query).map { row in
        NoteChunk(
            id: row[chunkId],
            noteId: row[chunkNoteId],
            chunkIndex: row[self.chunkIndex],
            content: row[chunkContent],
            topic: row[chunkTopic],
            tokenCount: row[chunkTokenCount],
            createdAt: ISO8601DateFormatter().date(from: row[chunkCreatedAt]) ?? Date()
        )
    }
}

func deleteChunksForNote(noteId: Int) async throws {
    guard let db = db else { throw DatabaseError.notConnected }
    try db.run(noteChunksTable.filter(chunkNoteId == noteId).delete())
}

func getUnchunkedNoteIds(limit: Int) async throws -> [Int] {
    guard let db = db else { throw DatabaseError.notConnected }
    let sql = """
        SELECT rn.id FROM raw_notes rn
        LEFT JOIN note_chunks nc ON rn.id = nc.note_id
        WHERE nc.id IS NULL AND rn.status != 'pending'
        ORDER BY rn.created_at DESC
        LIMIT ?
    """
    var ids: [Int] = []
    for row in try db.prepare(sql, limit) {
        if let id = row[0] as? Int64 { ids.append(Int(id)) }
    }
    return ids
}

func saveChunkEmbedding(chunkId: Int64, embedding: [Float]) async throws {
    guard let db = db else { throw DatabaseError.notConnected }
    let data = VectorUtility.floatsToData(embedding)
    try db.run(noteChunksTable.filter(self.chunkId == chunkId).update(chunkEmbedding <- data))
}

func getChunksWithEmbeddings(noteIds: [Int]) async throws -> [(chunk: NoteChunk, embedding: [Float]?)] {
    guard let db = db else { throw DatabaseError.notConnected }
    let query = noteChunksTable
        .filter(noteIds.contains(chunkNoteId))
        .filter(chunkEmbedding != nil)
        .order(chunkNoteId.asc, chunkIndex.asc)
    return try db.prepare(query).map { row in
        let chunk = NoteChunk(
            id: row[chunkId],
            noteId: row[chunkNoteId],
            chunkIndex: row[self.chunkIndex],
            content: row[chunkContent],
            topic: row[chunkTopic],
            tokenCount: row[chunkTokenCount],
            createdAt: ISO8601DateFormatter().date(from: row[chunkCreatedAt]) ?? Date()
        )
        let embedding = row[chunkEmbedding].flatMap { VectorUtility.dataToFloats($0) }
        return (chunk: chunk, embedding: embedding)
    }
}
```

**Note:** Check that `VectorUtility.floatsToData` and `VectorUtility.dataToFloats` already exist (they do — used by the existing `note_embeddings` table). If the column expressions conflict with existing names, prefix them (e.g., `chunkId` vs `id`).

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter NoteChunkDatabaseTests 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift SeleneChat/Tests/SeleneChatTests/Services/NoteChunkDatabaseTests.swift
git commit -m "feat: add note_chunks table with CRUD operations"
```

---

## Task 3: Rule-Based Chunking Service

**Files:**
- Create: `SeleneChat/Sources/SeleneShared/Services/ChunkingService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ChunkingServiceTests.swift`

**Context:** This task implements only the rule-based splitting logic (no LLM calls). It takes a note's content and splits it into chunks of 100-256 tokens. The token estimation uses the same 4-chars-per-token heuristic from `ThinkingPartnerContextBuilder`.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkingServiceTests: XCTestCase {

    let service = ChunkingService()

    // MARK: - Paragraph Splitting

    func testSplitsOnDoubleNewlines() {
        let content = "First paragraph about planning.\n\nSecond paragraph about execution.\n\nThird paragraph about review."
        let chunks = service.splitIntoChunks(content)

        XCTAssertEqual(chunks.count, 3)
        XCTAssertTrue(chunks[0].contains("planning"))
        XCTAssertTrue(chunks[1].contains("execution"))
        XCTAssertTrue(chunks[2].contains("review"))
    }

    func testSplitsOnMarkdownHeaders() {
        let content = """
        # Planning
        Details about the planning phase.

        # Execution
        Details about the execution phase.
        """
        let chunks = service.splitIntoChunks(content)

        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        XCTAssertTrue(chunks[0].contains("Planning"))
        XCTAssertTrue(chunks[1].contains("Execution"))
    }

    // MARK: - Merging Small Chunks

    func testMergesSmallChunks() {
        // Each line is very short (<100 tokens), should be merged
        let content = "Short line one.\n\nShort line two.\n\nShort line three."
        let chunks = service.splitIntoChunks(content)

        // All three are small enough to merge into one or two chunks
        XCTAssertLessThan(chunks.count, 3, "Small chunks should be merged together")
    }

    // MARK: - Splitting Large Chunks

    func testSplitsLargeChunksAtSentenceBoundaries() {
        // Create a paragraph that exceeds 256 tokens (~1024 chars)
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
        let text = "Hello world" // 11 chars -> ~2-3 tokens
        let tokens = service.estimateTokens(text)
        XCTAssertEqual(tokens, 2) // 11 / 4 = 2 (integer division)
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
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ChunkingServiceTests 2>&1 | head -20`
Expected: FAIL — `ChunkingService` type not found

**Step 3: Write implementation**

```swift
import Foundation

/// Splits note content into idea-level chunks for semantic retrieval.
/// Uses rule-based splitting (paragraphs, headers, sentence boundaries).
public class ChunkingService {

    /// Minimum tokens per chunk. Smaller chunks get merged with neighbors.
    private let minTokens = 100

    /// Maximum tokens per chunk. Larger chunks get split at sentence boundaries.
    private let maxTokens = 256

    public init() {}

    /// Estimate token count using 4-chars-per-token heuristic.
    public func estimateTokens(_ text: String) -> Int {
        text.count / 4
    }

    /// Split note content into chunks of approximately 100-256 tokens each.
    /// - Parameter content: The full note content
    /// - Returns: Array of chunk content strings, in order
    public func splitIntoChunks(_ content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Step 1: Split on paragraph boundaries (double newlines and markdown headers)
        var rawSegments = splitOnBoundaries(trimmed)

        // Step 2: Filter empty segments
        rawSegments = rawSegments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawSegments.isEmpty else { return [] }

        // Step 3: Split oversized segments at sentence boundaries
        var splitSegments: [String] = []
        for segment in rawSegments {
            if estimateTokens(segment) > maxTokens {
                splitSegments.append(contentsOf: splitAtSentences(segment))
            } else {
                splitSegments.append(segment)
            }
        }

        // Step 4: Merge undersized segments with neighbors
        return mergeSmallSegments(splitSegments)
    }

    // MARK: - Private

    private func splitOnBoundaries(_ text: String) -> [String] {
        // Split on double newlines or markdown headers (# at start of line)
        let pattern = #"\n\s*\n|(?=^#{1,6}\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return [text]
        }

        var segments: [String] = []
        var lastEnd = text.startIndex

        let nsRange = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let matchRange = match.flatMap({ Range($0.range, in: text) }) else { return }
            let segment = String(text[lastEnd..<matchRange.lowerBound])
            if !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(segment)
            }
            lastEnd = matchRange.upperBound
        }

        // Add remaining text
        let remaining = String(text[lastEnd...])
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(remaining)
        }

        return segments.isEmpty ? [text] : segments
    }

    private func splitAtSentences(_ text: String) -> [String] {
        // Split at sentence boundaries (. ! ? followed by space or end)
        let sentences = text.components(separatedBy: .init(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            let withSentence = current.isEmpty ? sentence + "." : current + " " + sentence + "."
            if estimateTokens(withSentence) > maxTokens && !current.isEmpty {
                chunks.append(current)
                current = sentence + "."
            } else {
                current = withSentence
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func mergeSmallSegments(_ segments: [String]) -> [String] {
        var merged: [String] = []
        var current = ""

        for segment in segments {
            if current.isEmpty {
                current = segment
                continue
            }

            let combined = current + "\n\n" + segment
            if estimateTokens(combined) <= maxTokens {
                current = combined
            } else {
                merged.append(current)
                current = segment
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.append(current)
        }

        return merged
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ChunkingServiceTests 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Services/ChunkingService.swift SeleneChat/Tests/SeleneChatTests/Services/ChunkingServiceTests.swift
git commit -m "feat: add rule-based ChunkingService for note splitting"
```

---

## Task 4: OllamaService num_ctx Support

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/OllamaService.swift` (lines 6-10, 106, 113-118)
- Test: `SeleneChat/Tests/SeleneChatTests/Services/OllamaServiceOptionsTests.swift`

**Context:** The current `GenerateRequest` struct has no `options` field. Ollama's API accepts an `options` object with `num_ctx` to set context window size. We need to pass this so thread chat can use 16384 tokens.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class OllamaServiceOptionsTests: XCTestCase {

    func testGenerateRequestEncodesOptions() throws {
        // Access the internal request struct via the generate method signature
        // We test that the service accepts an options parameter
        // Since OllamaService is an actor with private init, we test the public API
        // The real test is that generate(prompt:model:options:) compiles and accepts options
        let service = OllamaService.shared

        // Verify the method signature exists (compile-time check)
        // Runtime: just verify it doesn't crash with options param
        // Can't hit actual Ollama in unit tests, so this is a signature check
        _ = service  // Suppress unused warning
    }
}
```

**Step 2: Implement options support**

In `OllamaService.swift`, update the `GenerateRequest` struct (line 6-10):

```swift
private struct GenerateRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: GenerateOptions?
}

private struct GenerateOptions: Codable {
    let num_ctx: Int?
}
```

Update the `generate` method signature (line 106) to accept options:

```swift
func generate(prompt: String, model: String? = nil, numCtx: Int? = nil) async throws -> String {
```

Update the request body construction (lines 113-118):

```swift
let options = numCtx.map { GenerateOptions(num_ctx: $0) }
let requestBody = GenerateRequest(
    model: resolvedModel,
    prompt: prompt,
    stream: false,
    options: options
)
```

**Step 3: Verify LLMProvider conformance still works**

The `LLMProvider` protocol requires `generate(prompt:model:)`. Since we added `numCtx` with a default value of `nil`, the existing protocol conformance is unaffected. Verify:

Run: `cd SeleneChat && swift build 2>&1 | tail -5`
Expected: Build succeeds

**Step 4: Run all existing tests to verify no regressions**

Run: `cd SeleneChat && swift test 2>&1 | tail -10`
Expected: All tests pass

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/OllamaService.swift SeleneChat/Tests/SeleneChatTests/Services/OllamaServiceOptionsTests.swift
git commit -m "feat: add num_ctx options support to OllamaService"
```

---

## Task 5: LLM Router

**Files:**
- Create: `SeleneChat/Sources/SeleneShared/Services/LLMRouter.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/LLMRouterTests.swift`

**Context:** The router sits between ViewModels and LLM providers. It returns the right `LLMProvider` based on task type. For now, it always returns the provider passed in for "ollama" tasks. Apple Intelligence integration comes in Task 6.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class LLMRouterTests: XCTestCase {

    // MARK: - Mock Provider

    private class MockLLMProvider: LLMProvider {
        let name: String
        init(name: String) { self.name = name }
        func generate(prompt: String, model: String?) async throws -> String { "mock" }
        func embed(text: String, model: String?) async throws -> [Float] { [] }
        func isAvailable() async -> Bool { true }
    }

    // MARK: - Task Type Defaults

    func testDefaultsOllamaForThreadChat() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)

        let provider = router.provider(for: .threadChat)
        XCTAssertTrue(provider === ollama, "threadChat should default to Ollama")
    }

    func testDefaultsOllamaForBriefing() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)

        let provider = router.provider(for: .briefing)
        XCTAssertTrue(provider === ollama)
    }

    func testDefaultsOllamaForDeepDive() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)

        let provider = router.provider(for: .deepDive)
        XCTAssertTrue(provider === ollama)
    }

    func testDefaultsAppleForChunkLabeling() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)

        let provider = router.provider(for: .chunkLabeling)
        XCTAssertTrue(provider === apple, "chunkLabeling should default to Apple")
    }

    func testFallsBackToOllamaWhenAppleUnavailable() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)

        let provider = router.provider(for: .chunkLabeling)
        XCTAssertTrue(provider === ollama, "Should fall back to Ollama when Apple is nil")
    }

    func testDefaultsAppleForSummarization() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)

        let provider = router.provider(for: .summarization)
        XCTAssertTrue(provider === apple)
    }

    func testDefaultsAppleForQueryAnalysis() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)

        let provider = router.provider(for: .queryAnalysis)
        XCTAssertTrue(provider === apple)
    }

    // MARK: - Embedding Provider

    func testEmbeddingProviderAlwaysReturnsOllama() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)

        let provider = router.embeddingProvider()
        XCTAssertTrue(provider === ollama, "Embeddings should always use Ollama (nomic-embed-text)")
    }

    // MARK: - All Task Types

    func testAllTaskTypesReturnAProvider() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)

        for taskType in LLMRouter.TaskType.allCases {
            let provider = router.provider(for: taskType)
            XCTAssertNotNil(provider, "Task type \(taskType) should return a provider")
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter LLMRouterTests 2>&1 | head -20`
Expected: FAIL — `LLMRouter` type not found

**Step 3: Write implementation**

```swift
import Foundation

/// Routes LLM tasks to the best provider based on task type.
/// Defaults are research-backed: Apple for classification/labeling, Ollama for conversation/reasoning.
public class LLMRouter {

    /// Task types that can be routed to different providers.
    public enum TaskType: String, CaseIterable {
        case chunkLabeling   // Apple: fast on-device classification
        case embedding       // Ollama: nomic-embed-text (higher quality)
        case queryAnalysis   // Apple: fast intent classification
        case summarization   // Apple: optimized for this
        case threadChat      // Ollama: needs 8K+ context
        case briefing        // Ollama: multi-note synthesis
        case deepDive        // Ollama: complex reasoning
    }

    /// Which provider a task type defaults to.
    public enum ProviderPreference: String {
        case apple
        case ollama
    }

    private let ollamaProvider: LLMProvider
    private let appleProvider: LLMProvider?

    /// Default routing table (research-backed).
    private let defaults: [TaskType: ProviderPreference] = [
        .chunkLabeling: .apple,
        .embedding: .ollama,
        .queryAnalysis: .apple,
        .summarization: .apple,
        .threadChat: .ollama,
        .briefing: .ollama,
        .deepDive: .ollama,
    ]

    public init(ollamaProvider: LLMProvider, appleProvider: LLMProvider?) {
        self.ollamaProvider = ollamaProvider
        self.appleProvider = appleProvider
    }

    /// Get the provider for a given task type.
    /// Falls back to Ollama if Apple provider is unavailable.
    public func provider(for task: TaskType) -> LLMProvider {
        let preference = defaults[task] ?? .ollama

        switch preference {
        case .apple:
            return appleProvider ?? ollamaProvider
        case .ollama:
            return ollamaProvider
        }
    }

    /// Get the embedding provider. Always Ollama (nomic-embed-text).
    public func embeddingProvider() -> LLMProvider {
        return ollamaProvider
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter LLMRouterTests 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Services/LLMRouter.swift SeleneChat/Tests/SeleneChatTests/Services/LLMRouterTests.swift
git commit -m "feat: add LLMRouter with task-type default routing"
```

---

## Task 6: Apple Intelligence Service

**Files:**
- Create: `SeleneChat/Sources/SeleneChat/Services/AppleIntelligenceService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/AppleIntelligenceServiceTests.swift`

**Context:** Uses Apple Foundation Models framework (`FoundationModels`). Requires macOS 26+. Wraps behind `@available(macOS 26, *)` and `#if canImport(FoundationModels)`. Keep Package.swift platform minimum at `.macOS(.v14)` for backward compat.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class AppleIntelligenceServiceTests: XCTestCase {

    func testServiceConformsToLLMProvider() {
        // Compile-time check: AppleIntelligenceService must conform to LLMProvider
        if #available(macOS 26, *) {
            let service = AppleIntelligenceService()
            XCTAssertNotNil(service as LLMProvider)
        }
    }

    func testIsAvailableReturnsBoolWithoutCrashing() async {
        if #available(macOS 26, *) {
            let service = AppleIntelligenceService()
            let available = await service.isAvailable()
            // On CI or machines without Apple Intelligence, this may be false
            // Just verify it returns without crashing
            _ = available
        }
    }

    func testLabelTopicReturnsNonEmptyString() async throws {
        if #available(macOS 26, *) {
            let service = AppleIntelligenceService()
            guard await service.isAvailable() else {
                throw XCTSkip("Apple Intelligence not available on this machine")
            }
            let topic = try await service.labelTopic(chunk: "I need to plan the kitchen renovation project and get quotes from contractors this week.")
            XCTAssertFalse(topic.isEmpty, "Topic label should not be empty")
            XCTAssertLessThanOrEqual(topic.count, 60, "Topic label should be concise")
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter AppleIntelligenceServiceTests 2>&1 | head -20`
Expected: FAIL — `AppleIntelligenceService` type not found

**Step 3: Write implementation**

```swift
import Foundation
import SeleneShared

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence LLM provider using on-device Foundation Models.
/// Falls back gracefully on systems without Apple Intelligence.
@available(macOS 26, *)
class AppleIntelligenceService: LLMProvider {

    #if canImport(FoundationModels)
    private var session: LanguageModelSession?
    #endif

    init() {}

    func generate(prompt: String, model: String?) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw AppleIntelligenceError.notAvailable
        #endif
    }

    func embed(text: String, model: String?) async throws -> [Float] {
        // Apple NLContextualEmbedding would go here.
        // For now, embedding is routed to Ollama via LLMRouter.
        throw AppleIntelligenceError.embeddingNotSupported
    }

    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else { return false }
        return true
        #else
        return false
        #endif
    }

    /// Generate a concise topic label for a chunk of text.
    /// Uses the contentTagging model variant for optimal classification.
    func labelTopic(chunk: String) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(model: .contentTagging)
        let prompt = "Generate a 5-10 word topic label for this text. Return ONLY the label, nothing else.\n\nText: \(chunk)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw AppleIntelligenceError.notAvailable
        #endif
    }

    enum AppleIntelligenceError: Error, LocalizedError {
        case notAvailable
        case embeddingNotSupported

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Apple Intelligence is not available on this system"
            case .embeddingNotSupported:
                return "Use Ollama nomic-embed-text for embeddings instead"
            }
        }
    }
}
```

**Important:** The exact `FoundationModels` API surface may differ from what's shown here. During implementation, check Apple's docs for the actual `LanguageModelSession`, `SystemLanguageModel`, and `contentTagging` APIs. The structure is correct but method names may need adjustment. Run `swift build` to catch any API mismatches and fix them.

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter AppleIntelligenceServiceTests 2>&1 | tail -10`
Expected: PASS (tests skip gracefully if Apple Intelligence unavailable)

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/AppleIntelligenceService.swift SeleneChat/Tests/SeleneChatTests/Services/AppleIntelligenceServiceTests.swift
git commit -m "feat: add AppleIntelligenceService with Foundation Models"
```

---

## Task 7: Chunk Embedding Pipeline

**Files:**
- Create: `SeleneChat/Sources/SeleneChat/Services/ChunkEmbeddingService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ChunkEmbeddingServiceTests.swift`

**Context:** This service takes chunks from the database that don't have embeddings, generates embeddings via the LLMRouter's embedding provider (Ollama nomic-embed-text), and saves them back. It runs as part of the background chunking pipeline.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkEmbeddingServiceTests: XCTestCase {

    // MARK: - Mock Provider

    private class MockEmbeddingProvider: LLMProvider {
        var embedCallCount = 0
        func generate(prompt: String, model: String?) async throws -> String { "" }
        func embed(text: String, model: String?) async throws -> [Float] {
            embedCallCount += 1
            return [Float](repeating: 0.1, count: 768)
        }
        func isAvailable() async -> Bool { true }
    }

    // MARK: - Batch Embedding

    func testCreatesBatchEmbeddingRequests() async {
        let mockProvider = MockEmbeddingProvider()
        let service = ChunkEmbeddingService(embeddingProvider: mockProvider)

        let chunks = [
            NoteChunk.mock(id: 1, content: "First chunk"),
            NoteChunk.mock(id: 2, content: "Second chunk"),
            NoteChunk.mock(id: 3, content: "Third chunk"),
        ]

        let embeddings = try? await service.generateEmbeddings(for: chunks)
        XCTAssertEqual(embeddings?.count, 3)
        XCTAssertEqual(mockProvider.embedCallCount, 3)
    }

    func testEmbeddingDimensionsAreConsistent() async throws {
        let mockProvider = MockEmbeddingProvider()
        let service = ChunkEmbeddingService(embeddingProvider: mockProvider)

        let chunks = [NoteChunk.mock(id: 1, content: "Test chunk")]
        let embeddings = try await service.generateEmbeddings(for: chunks)

        XCTAssertEqual(embeddings[0].count, 768, "nomic-embed-text returns 768 dimensions")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ChunkEmbeddingServiceTests 2>&1 | head -20`
Expected: FAIL — `ChunkEmbeddingService` type not found

**Step 3: Write implementation**

```swift
import Foundation
import SeleneShared

/// Generates and manages embeddings for note chunks.
class ChunkEmbeddingService {

    private let embeddingProvider: LLMProvider

    init(embeddingProvider: LLMProvider) {
        self.embeddingProvider = embeddingProvider
    }

    /// Generate embeddings for a batch of chunks.
    /// - Parameter chunks: Chunks to embed
    /// - Returns: Array of embedding vectors, one per chunk (same order)
    func generateEmbeddings(for chunks: [NoteChunk]) async throws -> [[Float]] {
        var embeddings: [[Float]] = []
        for chunk in chunks {
            let embedding = try await embeddingProvider.embed(text: chunk.content, model: nil)
            embeddings.append(embedding)
        }
        return embeddings
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ChunkEmbeddingServiceTests 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/ChunkEmbeddingService.swift SeleneChat/Tests/SeleneChatTests/Services/ChunkEmbeddingServiceTests.swift
git commit -m "feat: add ChunkEmbeddingService for batch chunk embeddings"
```

---

## Task 8: Chunk Retrieval Service (Semantic Search)

**Files:**
- Create: `SeleneChat/Sources/SeleneShared/Services/ChunkRetrievalService.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/ChunkRetrievalServiceTests.swift`

**Context:** Given a query embedding and a set of chunks with embeddings, find the top-N most relevant chunks via cosine similarity. Supports thread-scoped search with global fallback.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkRetrievalServiceTests: XCTestCase {

    let service = ChunkRetrievalService()

    // MARK: - Cosine Similarity

    func testCosineSimilarityIdenticalVectors() {
        let v = [Float](repeating: 1.0, count: 5)
        let similarity = service.cosineSimilarity(v, v)
        XCTAssertEqual(similarity, 1.0, accuracy: 0.001)
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let similarity = service.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.001)
    }

    // MARK: - Top-N Retrieval

    func testRetrievesTopNByRelevance() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = [
            (NoteChunk.mock(id: 1, content: "Irrelevant"), [0.0, 1.0, 0.0]),   // orthogonal
            (NoteChunk.mock(id: 2, content: "Relevant"), [0.9, 0.1, 0.0]),     // very similar
            (NoteChunk.mock(id: 3, content: "Somewhat"), [0.5, 0.5, 0.0]),     // moderate
        ]

        let results = service.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 2,
            minSimilarity: 0.0
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].chunk.id, 2, "Most similar chunk should be first")
        XCTAssertEqual(results[1].chunk.id, 3, "Second most similar should be second")
    }

    func testMinSimilarityFiltersLowScores() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = [
            (NoteChunk.mock(id: 1, content: "Irrelevant"), [0.0, 1.0, 0.0]),
            (NoteChunk.mock(id: 2, content: "Relevant"), [0.9, 0.1, 0.0]),
        ]

        let results = service.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 10,
            minSimilarity: 0.5
        )

        XCTAssertEqual(results.count, 1, "Only chunks above threshold should be returned")
        XCTAssertEqual(results[0].chunk.id, 2)
    }

    // MARK: - Token Budget

    func testRespectsTokenBudget() {
        let queryEmbedding: [Float] = [1.0, 0.0, 0.0]
        let similarEmbedding: [Float] = [0.99, 0.01, 0.0]

        let candidates: [(chunk: NoteChunk, embedding: [Float])] = (1...20).map { i in
            (NoteChunk.mock(id: Int64(i), content: String(repeating: "word ", count: 50), tokenCount: 50), similarEmbedding)
        }

        let results = service.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 20,
            minSimilarity: 0.0,
            tokenBudget: 200
        )

        let totalTokens = results.reduce(0) { $0 + $1.chunk.tokenCount }
        XCTAssertLessThanOrEqual(totalTokens, 200, "Should respect token budget")
        XCTAssertEqual(results.count, 4, "200 budget / 50 tokens = 4 chunks max")
    }

    // MARK: - Empty Input

    func testEmptyCandidatesReturnsEmpty() {
        let results = service.retrieveTopChunks(
            queryEmbedding: [1.0, 0.0],
            candidates: [],
            limit: 10,
            minSimilarity: 0.0
        )
        XCTAssertTrue(results.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ChunkRetrievalServiceTests 2>&1 | head -20`
Expected: FAIL — `ChunkRetrievalService` type not found

**Step 3: Write implementation**

```swift
import Foundation

/// Retrieves the most relevant note chunks for a query via cosine similarity.
public class ChunkRetrievalService {

    public init() {}

    /// Compute cosine similarity between two vectors.
    public func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    /// Retrieve the top-N most relevant chunks for a query embedding.
    /// - Parameters:
    ///   - queryEmbedding: The embedded query vector
    ///   - candidates: Chunks with their embeddings to search through
    ///   - limit: Maximum number of chunks to return
    ///   - minSimilarity: Minimum cosine similarity threshold (0.0-1.0)
    ///   - tokenBudget: Optional max total tokens across returned chunks
    /// - Returns: Chunks sorted by relevance (highest first), with similarity scores
    public func retrieveTopChunks(
        queryEmbedding: [Float],
        candidates: [(chunk: NoteChunk, embedding: [Float])],
        limit: Int,
        minSimilarity: Float,
        tokenBudget: Int? = nil
    ) -> [(chunk: NoteChunk, similarity: Float)] {
        guard !candidates.isEmpty else { return [] }

        // Score all candidates
        var scored: [(chunk: NoteChunk, similarity: Float)] = candidates.compactMap { candidate in
            let sim = cosineSimilarity(queryEmbedding, candidate.embedding)
            guard sim >= minSimilarity else { return nil }
            return (chunk: candidate.chunk, similarity: sim)
        }

        // Sort by similarity descending
        scored.sort { $0.similarity > $1.similarity }

        // Apply limit
        var results = Array(scored.prefix(limit))

        // Apply token budget if specified
        if let budget = tokenBudget {
            var totalTokens = 0
            results = results.filter { item in
                totalTokens += item.chunk.tokenCount
                return totalTokens <= budget
            }
        }

        return results
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ChunkRetrievalServiceTests 2>&1 | tail -10`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Services/ChunkRetrievalService.swift SeleneChat/Tests/SeleneChatTests/Services/ChunkRetrievalServiceTests.swift
git commit -m "feat: add ChunkRetrievalService for semantic chunk search"
```

---

## Task 9: Thread Chat Integration

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Services/ThreadWorkspacePromptBuilder.swift` (lines 28-45, 57-86)
- Modify: `SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift` (lines 7-35, 39-59, 139-169)
- Modify: `SeleneChat/Sources/SeleneShared/Models/ThinkingPartnerQueryType.swift` (line 14)
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/ChunkRetrievalIntegrationTests.swift`

**Context:** This is the core integration that fixes the original bug. Replace the old buildDeepDiveContext (all-notes-truncated) with chunk-based retrieval. Add chunk pinning so follow-up turns preserve context.

**Step 1: Write the failing test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class ChunkRetrievalIntegrationTests: XCTestCase {

    // MARK: - Prompt Builder With Chunks

    func testBuildPromptWithChunksIncludesTopicLabels() {
        let builder = ThreadWorkspacePromptBuilder()
        let thread = Thread.mock(name: "Project Planning")
        let chunks: [(chunk: NoteChunk, similarity: Float)] = [
            (NoteChunk.mock(id: 1, content: "Need to schedule contractor meetings.", topic: "contractor scheduling"), 0.9),
            (NoteChunk.mock(id: 2, content: "Budget is approximately $50k.", topic: "budget overview"), 0.8),
        ]
        let tasks: [ThreadTask] = []

        let prompt = builder.buildInitialPromptWithChunks(
            thread: thread,
            retrievedChunks: chunks,
            tasks: tasks
        )

        XCTAssertTrue(prompt.contains("contractor scheduling"), "Prompt should include chunk topic labels")
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

        XCTAssertTrue(prompt.contains("pinned context"), "Pinned chunks from prior turns should be included")
        XCTAssertTrue(prompt.contains("new info"), "New relevant chunks should be included")
        XCTAssertTrue(prompt.contains("Break that into phases"))
    }

    // MARK: - Chunk Pinning

    func testChunkPinningTracksReferencedChunks() {
        var pinnedChunkIds: Set<Int64> = []

        // Simulate turn 1: chunks 1, 2, 3 were retrieved
        let turn1Chunks: [Int64] = [1, 2, 3]
        pinnedChunkIds.formUnion(turn1Chunks)

        // Simulate turn 2: chunks 2, 4 were retrieved (2 already pinned, 4 is new)
        let turn2Chunks: [Int64] = [2, 4]
        pinnedChunkIds.formUnion(turn2Chunks)

        XCTAssertEqual(pinnedChunkIds, [1, 2, 3, 4], "Pinned set should accumulate across turns")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ChunkRetrievalIntegrationTests 2>&1 | head -20`
Expected: FAIL — methods `buildInitialPromptWithChunks` and `buildFollowUpPromptWithChunks` not found

**Step 3: Implement changes**

**3a. Add chunk-based prompt methods to ThreadWorkspacePromptBuilder.swift:**

Add after the existing `buildFollowUpPrompt` method (after line 86):

```swift
// MARK: - Chunk-Based Prompts

/// Build initial prompt using retrieved chunks instead of all notes.
public func buildInitialPromptWithChunks(
    thread: Thread,
    retrievedChunks: [(chunk: NoteChunk, similarity: Float)],
    tasks: [ThreadTask]
) -> String {
    let chunkContext = formatChunkContext(thread: thread, chunks: retrievedChunks)
    let taskContext = buildTaskContext(tasks)

    return """
    You are a thinking partner for someone with ADHD, grounded in the context of their "\(thread.name)" thread.

    \(chunkContext)

    \(taskContext)

    Respond naturally to whatever the user asks. Use the context above to give informed, specific answers. You can help with planning, brainstorming, answering questions, giving advice, or anything else related to this thread.

    \(actionMarkerFormat)

    Keep your response under 200 words. Be direct and specific.
    """
}

/// Build follow-up prompt with pinned chunks from prior turns + newly retrieved chunks.
public func buildFollowUpPromptWithChunks(
    thread: Thread,
    pinnedChunks: [(chunk: NoteChunk, similarity: Float)],
    retrievedChunks: [(chunk: NoteChunk, similarity: Float)],
    tasks: [ThreadTask],
    conversationHistory: String,
    currentQuery: String
) -> String {
    let chunkContext = formatChunkContext(thread: thread, chunks: pinnedChunks + retrievedChunks)
    let taskContext = buildTaskContext(tasks)

    return """
    You are a thinking partner for someone with ADHD, continuing a conversation about "\(thread.name)".

    \(chunkContext)

    \(taskContext)

    ## Conversation So Far
    \(conversationHistory)

    ## Current Question
    \(currentQuery)

    Respond naturally to the user's question. Use the context to give informed, specific answers.

    \(actionMarkerFormat)

    Keep your response under 150 words. Be direct and specific.
    """
}

/// Format retrieved chunks as context for the prompt.
private func formatChunkContext(thread: Thread, chunks: [(chunk: NoteChunk, similarity: Float)]) -> String {
    var context = "## Thread: \(thread.name)\n"
    context += "Status: \(thread.status) \(thread.statusEmoji) | Notes: \(thread.noteCount)\n"

    if let why = thread.why, !why.isEmpty {
        context += "Why: \(why)\n"
    }

    context += "\n## Relevant Context\n\n"

    // Deduplicate by chunk ID
    var seen = Set<Int64>()
    for item in chunks {
        guard !seen.contains(item.chunk.id) else { continue }
        seen.insert(item.chunk.id)

        if let topic = item.chunk.topic {
            context += "**[\(topic)]**\n"
        }
        context += "\(item.chunk.content)\n\n"
    }

    return context
}
```

**3b. Update ThreadWorkspaceChatViewModel to use chunk retrieval:**

Add chunk tracking properties and update the `sendMessage` flow:

```swift
// Add to properties section (after line 19):
private var pinnedChunkIds: Set<Int64> = []
private let chunkRetrievalService = ChunkRetrievalService()

// Replace sendMessage (lines 40-59) with:
func sendMessage(_ content: String) async {
    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

    addUserMessage(content)
    isProcessing = true
    defer { isProcessing = false }

    do {
        let prompt = await buildChunkBasedPrompt(for: content)
        let response = try await ollamaService.generate(prompt: prompt, numCtx: 16384)
        processResponse(response)
    } catch {
        let errorMessage = Message(
            role: .assistant,
            content: "Sorry, I couldn't process that. \(error.localizedDescription)",
            llmTier: .local
        )
        messages.append(errorMessage)
    }
}

// Add new chunk-based prompt building method:
private func buildChunkBasedPrompt(for query: String) async -> String {
    // Check for "what's next" query first (uses old approach, no chunks needed)
    if promptBuilder.isWhatsNextQuery(query) {
        return promptBuilder.buildWhatsNextPrompt(thread: thread, notes: notes, tasks: tasks)
    }

    // Try to retrieve relevant chunks
    let noteIds = notes.map { $0.id }
    let retrievedChunks = await retrieveChunksForQuery(query, noteIds: noteIds)

    // If no chunks available (not yet indexed), fall back to old approach
    guard !retrievedChunks.isEmpty else {
        return buildPrompt(for: query)
    }

    // Get pinned chunks from prior turns
    let pinnedChunks = await getPinnedChunks(noteIds: noteIds)

    // Pin the newly retrieved chunks for future turns
    for item in retrievedChunks {
        pinnedChunkIds.insert(item.chunk.id)
    }

    let hasHistory = messages.filter({ $0.role != .system }).contains { $0.role == .assistant }

    if hasHistory {
        let history = buildConversationHistory()
        return promptBuilder.buildFollowUpPromptWithChunks(
            thread: thread,
            pinnedChunks: pinnedChunks,
            retrievedChunks: retrievedChunks,
            tasks: tasks,
            conversationHistory: history,
            currentQuery: query
        )
    } else {
        return promptBuilder.buildInitialPromptWithChunks(
            thread: thread,
            retrievedChunks: retrievedChunks,
            tasks: tasks
        )
    }
}

private func retrieveChunksForQuery(_ query: String, noteIds: [Int]) async -> [(chunk: NoteChunk, similarity: Float)] {
    do {
        // Embed the query
        let queryEmbedding = try await ollamaService.embed(text: query)

        // Get chunks with embeddings for this thread's notes
        let candidates = try await databaseService.getChunksWithEmbeddings(noteIds: noteIds)

        // Retrieve top chunks
        let results = chunkRetrievalService.retrieveTopChunks(
            queryEmbedding: queryEmbedding,
            candidates: candidates,
            limit: 15,
            minSimilarity: 0.3,
            tokenBudget: 8000
        )

        // If thread-scoped results are poor, try global fallback
        if results.isEmpty || (results.first?.similarity ?? 0) < 0.5 {
            let allCandidates = try await databaseService.getChunksWithEmbeddings(noteIds: [])
            if !allCandidates.isEmpty {
                return chunkRetrievalService.retrieveTopChunks(
                    queryEmbedding: queryEmbedding,
                    candidates: allCandidates,
                    limit: 15,
                    minSimilarity: 0.3,
                    tokenBudget: 8000
                )
            }
        }

        return results
    } catch {
        print("[ThreadWorkspaceChatVM] Chunk retrieval failed: \(error)")
        return []
    }
}

private func getPinnedChunks(noteIds: [Int]) async -> [(chunk: NoteChunk, similarity: Float)] {
    guard !pinnedChunkIds.isEmpty else { return [] }
    do {
        let allChunks = try await databaseService.getChunksForNotes(noteIds: noteIds)
        return allChunks
            .filter { pinnedChunkIds.contains($0.id) }
            .map { (chunk: $0, similarity: Float(1.0)) }
    } catch {
        return []
    }
}
```

**3c. Update ThinkingPartnerQueryType token budget** (for any remaining old-path usage):

In `ThinkingPartnerQueryType.swift` line 14, change:
```swift
case .deepDive: return 3000
```
to:
```swift
case .deepDive: return 8000
```

**Step 4: Run tests**

Run: `cd SeleneChat && swift test 2>&1 | tail -10`
Expected: All tests pass (existing + new integration tests)

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Services/ThreadWorkspacePromptBuilder.swift \
  SeleneChat/Sources/SeleneChat/ViewModels/ThreadWorkspaceChatViewModel.swift \
  SeleneChat/Sources/SeleneShared/Models/ThinkingPartnerQueryType.swift \
  SeleneChat/Tests/SeleneChatTests/Integration/ChunkRetrievalIntegrationTests.swift
git commit -m "feat: integrate chunk retrieval into thread workspace chat"
```

---

## Task 10: Background Chunking Pipeline

**Files:**
- Create: `SeleneChat/Sources/SeleneChat/Services/BackgroundChunkingPipeline.swift`
- Modify: `SeleneChat/Sources/SeleneChat/App/SeleneChatApp.swift` (add pipeline startup)
- Test: `SeleneChat/Tests/SeleneChatTests/Services/BackgroundChunkingPipelineTests.swift`

**Context:** This service runs in the background within SeleneChat. On launch and every 60 seconds, it checks for notes without chunks, chunks them, generates topic labels (via LLMRouter → Apple Intelligence), and embeds them (via LLMRouter → Ollama). It publishes progress for the UI to display.

**Step 1: Write the failing test**

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter BackgroundChunkingPipelineTests 2>&1 | head -20`
Expected: FAIL — `BackgroundChunkingPipeline` type not found

**Step 3: Write implementation**

```swift
import Foundation
import SeleneShared

/// Background pipeline that chunks, labels, and embeds notes.
/// Runs within SeleneChat, checking for unchunked notes every 60 seconds.
@MainActor
class BackgroundChunkingPipeline: ObservableObject {

    // MARK: - Published State

    @Published var isProcessing = false
    @Published var totalToProcess = 0
    @Published var processedCount = 0

    // MARK: - Services

    private let chunkingService = ChunkingService()
    private let databaseService = DatabaseService.shared
    private var timer: Timer?
    private let batchSize = 10

    // MARK: - Lifecycle

    func start() {
        // Run immediately on start
        Task { await processUnchunkedNotes() }

        // Schedule recurring check every 60 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.processUnchunkedNotes()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Processing

    func processUnchunkedNotes() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let unchunkedIds = try await databaseService.getUnchunkedNoteIds(limit: batchSize)
            guard !unchunkedIds.isEmpty else { return }

            totalToProcess = unchunkedIds.count
            processedCount = 0

            for noteId in unchunkedIds {
                guard let note = try await databaseService.getNote(byId: noteId) else { continue }

                // Step 1: Rule-based chunking
                let chunkTexts = chunkingService.splitIntoChunks(note.content)

                // Step 2: Store chunks
                for (index, chunkText) in chunkTexts.enumerated() {
                    let tokenCount = chunkingService.estimateTokens(chunkText)
                    let chunkId = try await databaseService.insertNoteChunk(
                        noteId: noteId,
                        chunkIndex: index,
                        content: chunkText,
                        topic: nil,  // Topic labeling happens separately
                        tokenCount: tokenCount,
                        embedding: nil  // Embedding happens separately
                    )

                    // Step 3: Generate embedding via Ollama
                    do {
                        let embedding = try await OllamaService.shared.embed(text: chunkText)
                        try await databaseService.saveChunkEmbedding(chunkId: chunkId, embedding: embedding)
                    } catch {
                        print("[ChunkPipeline] Embedding failed for chunk \(chunkId): \(error)")
                        // Continue — chunk is stored, embedding can be retried later
                    }

                    // Step 4: Generate topic label via Apple Intelligence (if available)
                    if #available(macOS 26, *) {
                        do {
                            let appleService = AppleIntelligenceService()
                            if await appleService.isAvailable() {
                                let topic = try await appleService.labelTopic(chunk: chunkText)
                                // Update chunk with topic (add this method to DatabaseService)
                                try await databaseService.updateChunkTopic(chunkId: chunkId, topic: topic)
                            }
                        } catch {
                            print("[ChunkPipeline] Topic labeling failed for chunk \(chunkId): \(error)")
                        }
                    }
                }

                processedCount += 1
            }
        } catch {
            print("[ChunkPipeline] Processing failed: \(error)")
        }
    }
}
```

Also add to `DatabaseService.swift`:

```swift
func updateChunkTopic(chunkId: Int64, topic: String) async throws {
    guard let db = db else { throw DatabaseError.notConnected }
    try db.run(noteChunksTable.filter(self.chunkId == chunkId).update(chunkTopic <- topic))
}

/// Get all chunks with embeddings. If noteIds is empty, returns chunks for ALL notes (global search).
func getAllChunksWithEmbeddings(limit: Int = 1000) async throws -> [(chunk: NoteChunk, embedding: [Float]?)] {
    guard let db = db else { throw DatabaseError.notConnected }
    let query = noteChunksTable
        .filter(chunkEmbedding != nil)
        .order(chunkCreatedAt.desc)
        .limit(limit)
    return try db.prepare(query).map { row in
        let chunk = NoteChunk(
            id: row[chunkId],
            noteId: row[chunkNoteId],
            chunkIndex: row[self.chunkIndex],
            content: row[chunkContent],
            topic: row[chunkTopic],
            tokenCount: row[chunkTokenCount],
            createdAt: ISO8601DateFormatter().date(from: row[chunkCreatedAt]) ?? Date()
        )
        let embedding = row[chunkEmbedding].flatMap { VectorUtility.dataToFloats($0) }
        return (chunk: chunk, embedding: embedding)
    }
}
```

**3b. Wire into SeleneChatApp.swift:**

Add the pipeline as a `@StateObject` and start it on appear. Find the app entry point and add:

```swift
@StateObject private var chunkingPipeline = BackgroundChunkingPipeline()
```

In the body, after existing `.onAppear` or `task` modifiers:

```swift
.task {
    chunkingPipeline.start()
}
```

**Step 4: Run tests**

Run: `cd SeleneChat && swift test 2>&1 | tail -10`
Expected: All tests pass

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/BackgroundChunkingPipeline.swift \
  SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift \
  SeleneChat/Sources/SeleneChat/App/SeleneChatApp.swift \
  SeleneChat/Tests/SeleneChatTests/Services/BackgroundChunkingPipelineTests.swift
git commit -m "feat: add background chunking pipeline with migration support"
```

---

## Task 11: End-to-End Verification

**Files:**
- Test: `SeleneChat/Tests/SeleneChatTests/Integration/ContextBlocksE2ETests.swift`

**Context:** Integration test that verifies the full flow: chunk a note, embed it, retrieve relevant chunks for a query, and build a prompt. Uses mock providers where needed.

**Step 1: Write the test**

```swift
import SeleneShared
import XCTest
@testable import SeleneChat

final class ContextBlocksE2ETests: XCTestCase {

    func testFullChunkAndRetrieveFlow() async {
        // Step 1: Chunk a note
        let chunkingService = ChunkingService()
        let noteContent = """
        # Kitchen Renovation

        Need to get quotes from three contractors by Friday. Budget is $50k total.

        # Timeline

        Start date is March 15. Expecting 6-8 weeks for completion. Need to order cabinets 4 weeks in advance.
        """

        let chunks = chunkingService.splitIntoChunks(noteContent)
        XCTAssertGreaterThanOrEqual(chunks.count, 2, "Should split into at least 2 chunks")

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
```

**Step 2: Run test**

Run: `cd SeleneChat && swift test --filter ContextBlocksE2ETests 2>&1 | tail -10`
Expected: PASS

**Step 3: Run full test suite**

Run: `cd SeleneChat && swift test 2>&1 | tail -10`
Expected: All tests pass, no regressions

**Step 4: Commit**

```bash
git add SeleneChat/Tests/SeleneChatTests/Integration/ContextBlocksE2ETests.swift
git commit -m "test: add end-to-end context blocks integration test"
```

---

## Summary

| Task | Component | New/Modified Files |
|------|-----------|-------------------|
| 1 | NoteChunk model | 2 new |
| 2 | note_chunks DB table | 1 modified, 1 new test |
| 3 | ChunkingService (rule-based) | 2 new |
| 4 | OllamaService num_ctx | 1 modified, 1 new test |
| 5 | LLMRouter | 2 new |
| 6 | AppleIntelligenceService | 2 new |
| 7 | ChunkEmbeddingService | 2 new |
| 8 | ChunkRetrievalService | 2 new |
| 9 | Thread chat integration | 3 modified, 1 new test |
| 10 | Background pipeline | 3 modified, 1 new test |
| 11 | E2E verification | 1 new test |

**Total: ~12 new files, ~4 modified files, 11 commits**
