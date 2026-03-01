# Conversation Memory Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add persistent conversation memory to SeleneChat so it remembers facts from past conversations and injects them into context.

**Architecture:** SQLite tables for conversations + memories, Swift services for extraction/consolidation, Ollama for LLM-powered extraction and decisions.

**Tech Stack:** Swift/SwiftUI, SQLite.swift, Ollama API, TypeScript (background workflows)

---

## Task 1: Database Migration - Conversations Table

**Files:**
- Create: `database/migrations/015_conversation_memory.sql`

**Step 1: Write the migration SQL**

```sql
-- Migration: 015_conversation_memory.sql
-- Purpose: Create tables for conversation memory system
-- Date: 2026-02-04

-- Store raw chat history for memory extraction
CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at);

-- Extracted memories (facts learned from conversations)
CREATE TABLE IF NOT EXISTS conversation_memories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    source_session_id TEXT,
    embedding BLOB,
    memory_type TEXT CHECK(memory_type IN ('preference', 'fact', 'pattern', 'context')),
    confidence REAL DEFAULT 1.0,
    last_accessed TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_memories_type ON conversation_memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_memories_confidence ON conversation_memories(confidence);
CREATE INDEX IF NOT EXISTS idx_memories_last_accessed ON conversation_memories(last_accessed);
```

**Step 2: Apply migration to test database**

Run: `sqlite3 ~/selene/data-test/selene-test.db < database/migrations/015_conversation_memory.sql`
Expected: No output (success)

**Step 3: Verify tables exist**

Run: `sqlite3 ~/selene/data-test/selene-test.db ".schema conversations"`
Expected: Shows CREATE TABLE statement

**Step 4: Commit**

```bash
git add database/migrations/015_conversation_memory.sql
git commit -m "feat(db): add conversation memory tables

Add conversations table for chat history storage and
conversation_memories table for extracted facts.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Swift Migration - Create Tables in SeleneChat

**Files:**
- Create: `SeleneChat/Sources/Services/Migrations/Migration008_ConversationMemory.swift`
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift:157-160`

**Step 1: Write the Swift migration**

```swift
import Foundation
import SQLite

struct Migration008_ConversationMemory {
    static func run(db: Connection) throws {
        // Create conversations table
        try db.run("""
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                content TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)

        try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at)")

        // Create conversation_memories table
        try db.run("""
            CREATE TABLE IF NOT EXISTS conversation_memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT NOT NULL,
                source_session_id TEXT,
                embedding BLOB,
                memory_type TEXT CHECK(memory_type IN ('preference', 'fact', 'pattern', 'context')),
                confidence REAL DEFAULT 1.0,
                last_accessed TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)

        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_type ON conversation_memories(memory_type)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_confidence ON conversation_memories(confidence)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_last_accessed ON conversation_memories(last_accessed)")

        #if DEBUG
        DebugLogger.shared.log(.state, "Migration008_ConversationMemory: completed")
        #endif
    }
}
```

**Step 2: Register migration in DatabaseService.swift**

Add after line 160 (after Migration007):
```swift
try? Migration008_ConversationMemory.run(db: db!)
```

**Step 3: Build SeleneChat to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add SeleneChat/Sources/Services/Migrations/Migration008_ConversationMemory.swift
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(selenechat): add conversation memory migration

Creates conversations and conversation_memories tables
in SeleneChat database on startup.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Swift Model - ConversationMemory

**Files:**
- Create: `SeleneChat/Sources/Models/ConversationMemory.swift`

**Step 1: Write the model**

```swift
import Foundation

/// A memory extracted from conversations
struct ConversationMemory: Identifiable, Codable, Hashable {
    let id: Int64
    let content: String
    let sourceSessionId: String?
    let memoryType: MemoryType
    var confidence: Double
    var lastAccessed: Date?
    let createdAt: Date
    var updatedAt: Date

    enum MemoryType: String, Codable, CaseIterable {
        case preference
        case fact
        case pattern
        case context
    }

    init(
        id: Int64,
        content: String,
        sourceSessionId: String? = nil,
        memoryType: MemoryType,
        confidence: Double = 1.0,
        lastAccessed: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.sourceSessionId = sourceSessionId
        self.memoryType = memoryType
        self.confidence = confidence
        self.lastAccessed = lastAccessed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Models/ConversationMemory.swift
git commit -m "feat(selenechat): add ConversationMemory model

Represents an extracted fact/preference/pattern from conversations.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: DatabaseService - Conversation Storage Methods

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`

**Step 1: Add table/column definitions after line 120**

```swift
// conversations table
private let conversationsTable = Table("conversations")
private let convId = Expression<Int64>("id")
private let convSessionId = Expression<String>("session_id")
private let convRole = Expression<String>("role")
private let convContent = Expression<String>("content")
private let convCreatedAt = Expression<String>("created_at")

// conversation_memories table
private let memoriesTable = Table("conversation_memories")
private let memId = Expression<Int64>("id")
private let memContent = Expression<String>("content")
private let memSourceSessionId = Expression<String?>("source_session_id")
private let memEmbedding = Expression<SQLite.Blob?>("embedding")
private let memType = Expression<String?>("memory_type")
private let memConfidence = Expression<Double>("confidence")
private let memLastAccessed = Expression<String?>("last_accessed")
private let memCreatedAt = Expression<String>("created_at")
private let memUpdatedAt = Expression<String>("updated_at")
```

**Step 2: Add conversation storage methods before the Error Types section**

```swift
// MARK: - Conversation Storage

/// Save a conversation message
func saveConversationMessage(sessionId: UUID, role: String, content: String) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let now = iso8601Formatter.string(from: Date())

    try db.run(conversationsTable.insert(
        convSessionId <- sessionId.uuidString,
        convRole <- role,
        convContent <- content,
        convCreatedAt <- now
    ))

    #if DEBUG
    DebugLogger.shared.log(.state, "DatabaseService.conversationSaved: \(role) in \(sessionId)")
    #endif
}

/// Get recent messages for a session
func getRecentMessages(sessionId: UUID, limit: Int = 10) async throws -> [(role: String, content: String, createdAt: Date)] {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let query = conversationsTable
        .filter(convSessionId == sessionId.uuidString)
        .order(convCreatedAt.desc)
        .limit(limit)

    var messages: [(role: String, content: String, createdAt: Date)] = []

    for row in try db.prepare(query) {
        let role = row[convRole]
        let content = row[convContent]
        let createdAt = parseDateString(row[convCreatedAt]) ?? Date()
        messages.append((role: role, content: content, createdAt: createdAt))
    }

    // Return in chronological order
    return messages.reversed()
}

/// Get all recent messages across sessions (for context window)
func getAllRecentMessages(limit: Int = 10) async throws -> [(sessionId: String, role: String, content: String, createdAt: Date)] {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let query = conversationsTable
        .order(convCreatedAt.desc)
        .limit(limit)

    var messages: [(sessionId: String, role: String, content: String, createdAt: Date)] = []

    for row in try db.prepare(query) {
        let sessionId = row[convSessionId]
        let role = row[convRole]
        let content = row[convContent]
        let createdAt = parseDateString(row[convCreatedAt]) ?? Date()
        messages.append((sessionId: sessionId, role: role, content: content, createdAt: createdAt))
    }

    return messages.reversed()
}
```

**Step 3: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(selenechat): add conversation storage methods

- saveConversationMessage: stores chat messages
- getRecentMessages: retrieves session history
- getAllRecentMessages: retrieves cross-session history

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: DatabaseService - Memory Storage Methods

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`

**Step 1: Add memory storage methods after conversation methods**

```swift
// MARK: - Memory Storage

/// Insert a new memory
func insertMemory(content: String, type: ConversationMemory.MemoryType, confidence: Double, sourceSessionId: UUID?, embedding: [Float]? = nil) async throws -> Int64 {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let now = iso8601Formatter.string(from: Date())

    var setter: [Setter] = [
        memContent <- content,
        memType <- type.rawValue,
        memConfidence <- confidence,
        memCreatedAt <- now,
        memUpdatedAt <- now,
        memLastAccessed <- now
    ]

    if let sessionId = sourceSessionId {
        setter.append(memSourceSessionId <- sessionId.uuidString)
    }

    if let emb = embedding {
        let embeddingData = Data(bytes: emb, count: emb.count * MemoryLayout<Float>.size)
        setter.append(memEmbedding <- SQLite.Blob(bytes: [UInt8](embeddingData)))
    }

    let rowId = try db.run(memoriesTable.insert(setter))

    #if DEBUG
    DebugLogger.shared.log(.state, "DatabaseService.memoryInserted: \(content.prefix(50))...")
    #endif

    return rowId
}

/// Update an existing memory
func updateMemory(id: Int64, content: String, confidence: Double? = nil) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let now = iso8601Formatter.string(from: Date())
    let memory = memoriesTable.filter(memId == id)

    var setter: [Setter] = [
        memContent <- content,
        memUpdatedAt <- now
    ]

    if let conf = confidence {
        setter.append(memConfidence <- conf)
    }

    try db.run(memory.update(setter))

    #if DEBUG
    DebugLogger.shared.log(.state, "DatabaseService.memoryUpdated: \(id)")
    #endif
}

/// Delete a memory
func deleteMemory(id: Int64) async throws {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let memory = memoriesTable.filter(memId == id)
    try db.run(memory.delete())

    #if DEBUG
    DebugLogger.shared.log(.state, "DatabaseService.memoryDeleted: \(id)")
    #endif
}

/// Update last_accessed for memories (reinforcement)
func touchMemories(ids: [Int64]) async throws {
    guard let db = db, !ids.isEmpty else { return }

    let now = iso8601Formatter.string(from: Date())
    let memories = memoriesTable.filter(ids.contains(memId))
    try db.run(memories.update(memLastAccessed <- now))

    #if DEBUG
    DebugLogger.shared.log(.state, "DatabaseService.memoriesAccessed: \(ids.count) memories")
    #endif
}

/// Get all memories (for simple retrieval)
func getAllMemories(limit: Int = 50) async throws -> [ConversationMemory] {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let query = memoriesTable
        .order(memConfidence.desc, memLastAccessed.desc)
        .limit(limit)

    var memories: [ConversationMemory] = []

    for row in try db.prepare(query) {
        let memory = ConversationMemory(
            id: row[memId],
            content: row[memContent],
            sourceSessionId: row[memSourceSessionId],
            memoryType: ConversationMemory.MemoryType(rawValue: row[memType] ?? "fact") ?? .fact,
            confidence: row[memConfidence],
            lastAccessed: row[memLastAccessed].flatMap { parseDateString($0) },
            createdAt: parseDateString(row[memCreatedAt]) ?? Date(),
            updatedAt: parseDateString(row[memUpdatedAt]) ?? Date()
        )
        memories.append(memory)
    }

    return memories
}

/// Get memories with embeddings for vector search
func getMemoriesWithEmbeddings() async throws -> [(memory: ConversationMemory, embedding: [Float])] {
    guard let db = db else {
        throw DatabaseError.notConnected
    }

    let query = memoriesTable
        .filter(memEmbedding != nil)
        .filter(memConfidence > 0.1)

    var results: [(memory: ConversationMemory, embedding: [Float])] = []

    for row in try db.prepare(query) {
        guard let embBlob = row[memEmbedding] else { continue }

        let memory = ConversationMemory(
            id: row[memId],
            content: row[memContent],
            sourceSessionId: row[memSourceSessionId],
            memoryType: ConversationMemory.MemoryType(rawValue: row[memType] ?? "fact") ?? .fact,
            confidence: row[memConfidence],
            lastAccessed: row[memLastAccessed].flatMap { parseDateString($0) },
            createdAt: parseDateString(row[memCreatedAt]) ?? Date(),
            updatedAt: parseDateString(row[memUpdatedAt]) ?? Date()
        )

        // Convert blob to [Float]
        let bytes = embBlob.bytes
        let floatCount = bytes.count / MemoryLayout<Float>.size
        var embedding = [Float](repeating: 0, count: floatCount)
        _ = embedding.withUnsafeMutableBytes { destPtr in
            bytes.withUnsafeBytes { srcPtr in
                destPtr.copyMemory(from: srcPtr)
            }
        }

        results.append((memory: memory, embedding: embedding))
    }

    return results
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(selenechat): add memory storage methods

- insertMemory: stores extracted facts with embeddings
- updateMemory: updates existing memories
- deleteMemory: removes memories
- touchMemories: updates last_accessed for reinforcement
- getAllMemories: retrieves memories sorted by confidence
- getMemoriesWithEmbeddings: retrieves for vector search

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: MemoryService - Extraction and Consolidation

**Files:**
- Create: `SeleneChat/Sources/Services/MemoryService.swift`

**Step 1: Write the MemoryService**

```swift
import Foundation

/// Service for extracting and consolidating conversation memories
actor MemoryService {
    static let shared = MemoryService()

    private let ollamaService = OllamaService.shared
    private let databaseService = DatabaseService.shared

    private init() {}

    // MARK: - Types

    struct CandidateFact: Codable {
        let fact: String
        let type: String
        let confidence: Double
    }

    struct ExtractionResult: Codable {
        let facts: [CandidateFact]
    }

    enum ConsolidationAction: String, Codable {
        case ADD
        case UPDATE
        case DELETE
        case NOOP
    }

    struct ConsolidationDecision: Codable {
        let action: ConsolidationAction
        let memoryId: Int64?
        let merged: String?
        let reason: String?
    }

    // MARK: - Extraction

    /// Extract memories from a conversation exchange
    func extractMemories(
        userMessage: String,
        assistantResponse: String,
        recentMessages: [(role: String, content: String, createdAt: Date)]
    ) async throws -> [CandidateFact] {
        // Format recent messages
        let recentContext = recentMessages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")

        let prompt = """
        You are a memory extraction system for Selene, an ADHD-focused assistant.

        Given this conversation context and the latest exchange, extract any facts
        worth remembering about the user - their preferences, patterns, projects,
        or important context.

        RECENT MESSAGES:
        \(recentContext)

        CURRENT EXCHANGE:
        User: \(userMessage)
        Assistant: \(assistantResponse)

        Return ONLY valid JSON matching this exact format (no other text):
        {
          "facts": [
            {"fact": "description of fact", "type": "preference|fact|pattern|context", "confidence": 0.8}
          ]
        }

        Only extract facts that are genuinely useful for future conversations.
        Be selective, not exhaustive. If nothing worth remembering, return {"facts": []}.
        """

        let response = try await ollamaService.generate(prompt: prompt)

        // Parse JSON response
        guard let jsonData = response.data(using: .utf8) else {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.extractMemories: invalid response encoding")
            #endif
            return []
        }

        do {
            let result = try JSONDecoder().decode(ExtractionResult.self, from: jsonData)
            #if DEBUG
            DebugLogger.shared.log(.state, "MemoryService.extractMemories: extracted \(result.facts.count) facts")
            #endif
            return result.facts
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.extractMemories: JSON parse failed - \(error)")
            DebugLogger.shared.log(.error, "MemoryService.extractMemories: response was: \(response.prefix(500))")
            #endif
            return []
        }
    }

    // MARK: - Consolidation

    /// Consolidate a candidate fact with existing memories
    func consolidateMemory(
        candidateFact: CandidateFact,
        similarMemories: [ConversationMemory],
        sessionId: UUID
    ) async throws {
        // If no similar memories, just ADD
        if similarMemories.isEmpty {
            let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
            _ = try await databaseService.insertMemory(
                content: candidateFact.fact,
                type: memoryType,
                confidence: candidateFact.confidence,
                sourceSessionId: sessionId
            )
            #if DEBUG
            DebugLogger.shared.log(.state, "MemoryService.consolidate: ADD (no similar)")
            #endif
            return
        }

        // Ask LLM to decide
        let similarStr = similarMemories.enumerated().map { (i, m) in
            "\(i + 1). [id=\(m.id)] \(m.content)"
        }.joined(separator: "\n")

        let prompt = """
        You are managing a memory system. Given a new fact and existing similar
        memories, decide what to do.

        NEW FACT: "\(candidateFact.fact)"

        EXISTING SIMILAR MEMORIES:
        \(similarStr)

        Return ONLY valid JSON matching one of these formats (no other text):
        - {"action": "ADD"} - New information, nothing equivalent exists
        - {"action": "UPDATE", "memoryId": N, "merged": "combined fact text"} - Augment existing
        - {"action": "DELETE", "memoryId": N, "reason": "why"} - New fact contradicts this
        - {"action": "NOOP", "reason": "why"} - Already known or not worth storing

        Consider: Is this genuinely new? Does it contradict something? Is it worth remembering?
        """

        let response = try await ollamaService.generate(prompt: prompt)

        guard let jsonData = response.data(using: .utf8) else {
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.consolidate: invalid response encoding")
            #endif
            return
        }

        do {
            let decision = try JSONDecoder().decode(ConsolidationDecision.self, from: jsonData)

            switch decision.action {
            case .ADD:
                let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
                _ = try await databaseService.insertMemory(
                    content: candidateFact.fact,
                    type: memoryType,
                    confidence: candidateFact.confidence,
                    sourceSessionId: sessionId
                )
                #if DEBUG
                DebugLogger.shared.log(.state, "MemoryService.consolidate: ADD")
                #endif

            case .UPDATE:
                if let memoryId = decision.memoryId, let merged = decision.merged {
                    try await databaseService.updateMemory(id: memoryId, content: merged)
                    #if DEBUG
                    DebugLogger.shared.log(.state, "MemoryService.consolidate: UPDATE \(memoryId)")
                    #endif
                }

            case .DELETE:
                if let memoryId = decision.memoryId {
                    try await databaseService.deleteMemory(id: memoryId)
                    #if DEBUG
                    DebugLogger.shared.log(.state, "MemoryService.consolidate: DELETE \(memoryId)")
                    #endif
                }

            case .NOOP:
                #if DEBUG
                DebugLogger.shared.log(.state, "MemoryService.consolidate: NOOP - \(decision.reason ?? "no reason")")
                #endif
            }

        } catch {
            // If JSON parsing fails, default to ADD
            #if DEBUG
            DebugLogger.shared.log(.error, "MemoryService.consolidate: JSON parse failed, defaulting to ADD")
            #endif
            let memoryType = ConversationMemory.MemoryType(rawValue: candidateFact.type) ?? .fact
            _ = try await databaseService.insertMemory(
                content: candidateFact.fact,
                type: memoryType,
                confidence: candidateFact.confidence,
                sourceSessionId: sessionId
            )
        }
    }

    // MARK: - Retrieval

    /// Get relevant memories for a query (simple keyword match for MVP)
    func getRelevantMemories(for query: String, limit: Int = 5) async throws -> [ConversationMemory] {
        let allMemories = try await databaseService.getAllMemories(limit: 50)

        // Simple keyword matching for MVP
        let queryWords = Set(query.lowercased().split(separator: " ").map(String.init))

        let scored = allMemories.map { memory -> (memory: ConversationMemory, score: Double) in
            let contentWords = Set(memory.content.lowercased().split(separator: " ").map(String.init))
            let overlap = queryWords.intersection(contentWords).count
            let score = Double(overlap) * memory.confidence
            return (memory: memory, score: score)
        }

        let relevant = scored
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.memory }

        // Touch accessed memories
        if !relevant.isEmpty {
            try await databaseService.touchMemories(ids: relevant.map { $0.id })
        }

        #if DEBUG
        DebugLogger.shared.log(.state, "MemoryService.getRelevant: \(relevant.count) memories for query")
        #endif

        return relevant
    }
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/MemoryService.swift
git commit -m "feat(selenechat): add MemoryService for extraction and consolidation

- extractMemories: uses Ollama to extract facts from conversations
- consolidateMemory: ADD/UPDATE/DELETE/NOOP decisions via LLM
- getRelevantMemories: keyword-based retrieval for MVP

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Integrate Memory into ChatViewModel

**Files:**
- Modify: `SeleneChat/Sources/Services/ChatViewModel.swift`

**Step 1: Read current ChatViewModel to understand structure**

First, read the file to understand where to integrate.

**Step 2: Add memory injection to system prompt building**

Add a method to build system prompt with memories:
```swift
private func buildSystemPromptWithMemories(query: String) async -> String {
    var prompt = """
    You are Selene, an ADHD-focused assistant that helps with note organization and retrieval.

    """

    // Get relevant memories
    do {
        let memories = try await MemoryService.shared.getRelevantMemories(for: query, limit: 5)
        if !memories.isEmpty {
            prompt += "## What you remember about this user:\n"
            for memory in memories {
                prompt += "- \(memory.content)\n"
            }
            prompt += "\n"
        }
    } catch {
        #if DEBUG
        DebugLogger.shared.log(.error, "ChatViewModel.buildSystemPrompt: memory retrieval failed - \(error)")
        #endif
    }

    return prompt
}
```

**Step 3: Add memory extraction after response**

After assistant responds, trigger memory extraction:
```swift
private func extractMemoriesFromExchange(
    userMessage: String,
    assistantResponse: String,
    sessionId: UUID
) {
    Task {
        do {
            // Get recent messages for context
            let recentMessages = try await DatabaseService.shared.getRecentMessages(sessionId: sessionId, limit: 10)

            // Extract candidate facts
            let facts = try await MemoryService.shared.extractMemories(
                userMessage: userMessage,
                assistantResponse: assistantResponse,
                recentMessages: recentMessages
            )

            // Consolidate each fact
            for fact in facts {
                // Get all memories for simple comparison (MVP - no vector search yet)
                let allMemories = try await DatabaseService.shared.getAllMemories(limit: 20)
                try await MemoryService.shared.consolidateMemory(
                    candidateFact: fact,
                    similarMemories: allMemories,
                    sessionId: sessionId
                )
            }
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "ChatViewModel.extractMemories: failed - \(error)")
            #endif
        }
    }
}
```

**Step 4: Add conversation storage**

After each message exchange, save to conversations table:
```swift
private func saveConversationMessages(
    sessionId: UUID,
    userMessage: String,
    assistantResponse: String
) {
    Task {
        do {
            try await DatabaseService.shared.saveConversationMessage(
                sessionId: sessionId,
                role: "user",
                content: userMessage
            )
            try await DatabaseService.shared.saveConversationMessage(
                sessionId: sessionId,
                role: "assistant",
                content: assistantResponse
            )
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "ChatViewModel.saveConversation: failed - \(error)")
            #endif
        }
    }
}
```

**Step 5: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add SeleneChat/Sources/Services/ChatViewModel.swift
git commit -m "feat(selenechat): integrate memory into chat flow

- Inject relevant memories into system prompt
- Save conversation messages to database
- Extract memories after assistant responds

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Add OllamaService Embedding Method

**Files:**
- Modify: `SeleneChat/Sources/Services/OllamaService.swift`

**Step 1: Add embedding endpoint support**

Add after the generate method:
```swift
/// Generate embedding for text
/// - Parameters:
///   - text: The text to embed
///   - model: The embedding model (default: nomic-embed-text)
/// - Returns: Array of embedding floats
func embed(text: String, model: String = "nomic-embed-text") async throws -> [Float] {
    guard let url = URL(string: "\(baseURL)/api/embeddings") else {
        throw OllamaError.invalidResponse
    }

    struct EmbeddingRequest: Codable {
        let model: String
        let prompt: String
    }

    struct EmbeddingResponse: Codable {
        let embedding: [Float]
    }

    let requestBody = EmbeddingRequest(model: model, prompt: text)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)
    request.timeoutInterval = 30.0

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw OllamaError.serviceUnavailable
    }

    let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)

    #if DEBUG
    DebugLogger.shared.log(.state, "OllamaService.embed: success, dimensions=\(embeddingResponse.embedding.count)")
    #endif

    return embeddingResponse.embedding
}
```

**Step 2: Build to verify**

Run: `cd SeleneChat && swift build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add SeleneChat/Sources/Services/OllamaService.swift
git commit -m "feat(selenechat): add embedding support to OllamaService

Adds embed() method for generating embeddings via nomic-embed-text.
Prepares for vector-based memory retrieval.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 9: End-to-End Test

**Files:**
- No new files, testing existing integration

**Step 1: Build SeleneChat**

Run: `cd SeleneChat && swift build -c release`
Expected: Build succeeds

**Step 2: Start Ollama**

Run: `ollama serve` (in separate terminal if not running)
Expected: Ollama running on localhost:11434

**Step 3: Run SeleneChat and test memory flow**

Run: `.build/release/SeleneChat`

Test sequence:
1. Type: "I prefer dark mode in all my apps"
2. Wait for response
3. Close and reopen app
4. Type: "What do I like?"
5. Verify response mentions dark mode preference

**Step 4: Verify database**

Run: `sqlite3 ~/selene/data-test/selene-test.db "SELECT * FROM conversation_memories;"`
Expected: Shows extracted memory about dark mode preference

**Step 5: Commit final integration**

```bash
git add -A
git commit -m "feat(selenechat): conversation memory MVP complete

Phase 1 implementation:
- Conversations stored in SQLite
- Memories extracted via Ollama
- Basic consolidation (ADD/UPDATE/DELETE/NOOP)
- Memory injection into system prompt

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Summary

| Task | Description | Est. Time |
|------|-------------|-----------|
| 1 | Database migration - SQL | 10 min |
| 2 | Swift migration | 15 min |
| 3 | ConversationMemory model | 10 min |
| 4 | Conversation storage methods | 20 min |
| 5 | Memory storage methods | 25 min |
| 6 | MemoryService | 30 min |
| 7 | ChatViewModel integration | 25 min |
| 8 | OllamaService embedding | 15 min |
| 9 | End-to-end test | 15 min |

**Total:** ~165 min (~2.75 hours)

---

## Post-MVP Enhancements (Phase 2+)

Not in this plan, but next steps:
- Vector-based memory retrieval (using embeddings)
- Confidence decay workflow (TypeScript launchd job)
- Entity graph (memory_entities, memory_relationships tables)
- Conversation summary generation
