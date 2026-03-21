# SeleneChat Services Layer Context

## Purpose

Business logic layer for SeleneChat app. Encapsulates database access, LLM communication, note search, and citation extraction. Provides clean API for SwiftUI views.

## Tech Stack

- Swift 5.9+ (async/await, Actors)
- SQLite.swift for database queries
- URLSession for Ollama HTTP API
- Combine framework for reactive updates

## Key Files

- DatabaseService.swift - SQLite connection and CRUD operations
- SearchService.swift - Note search with relevance ranking
- OllamaService.swift - LLM API integration
- CitationService.swift (planned) - Extract and resolve citations

## Architecture

### Service Pattern
```
Views
  ↓
@EnvironmentObject / @StateObject
  ↓
Service (protocol)
  ↓
Implementation (class/actor)
```

### Dependency Injection
```swift
@main
struct SeleneChatApp: App {
    let databaseService = DatabaseService()
    let ollamaService = OllamaService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseService)
                .environmentObject(ollamaService)
        }
    }
}
```

## DatabaseService

### Responsibilities
- Open/close SQLite connection
- Query notes (raw_notes, processed_notes)
- Fetch by ID, search by content
- Handle test data filtering
- Thread-safe database access

### Common Patterns
```swift
import SQLite

actor DatabaseService: ObservableObject {
    private let db: Connection
    private let notesTable = Table("raw_notes")

    init(path: String = "./data/selene.db") throws {
        db = try Connection(path)
    }

    func fetchNote(id: Int64) async throws -> Note? {
        let query = notesTable.filter(id == id)
        guard let row = try db.pluck(query) else { return nil }
        return Note(from: row)
    }

    func searchNotes(query: String, limit: Int = 10) async throws -> [Note] {
        let contentCol = Expression<String>("content")
        let results = try db.prepare(
            notesTable
                .filter(contentCol.like("%\(query)%"))
                .limit(limit)
        )
        return results.map { Note(from: $0) }
    }
}
```

### Thread Safety
- Use `actor` for automatic synchronization
- All methods are `async` to prevent blocking
- Database connection is private

## OllamaService

### Responsibilities
- Communicate with Ollama HTTP API
- Format prompts with context
- Parse LLM responses
- Extract citations from responses
- Handle streaming responses (future)

### Common Patterns
```swift
actor OllamaService: ObservableObject {
    private let baseURL = "http://localhost:11434"

    func generateResponse(query: String, context: [Note]) async throws -> String {
        let prompt = buildPrompt(query: query, context: context)

        var request = URLRequest(url: URL(string: "\(baseURL)/api/generate")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "mistral:7b",
            "prompt": prompt,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OllamaError.requestFailed
        }

        let json = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return json.response
    }

    private func buildPrompt(query: String, context: [Note]) -> String {
        var prompt = "Answer this question based on the following notes:\n\n"

        for (index, note) in context.enumerated() {
            prompt += "[\(index + 1)] \(note.content)\n\n"
        }

        prompt += "Question: \(query)\n\n"
        prompt += "Answer with citations using [1], [2], etc. to reference notes above."

        return prompt
    }
}
```

## SearchService

### Responsibilities
- Full-text search across notes
- Relevance ranking (TF-IDF, BM25)
- Concept-based search (using processed_notes)
- Date-based filtering
- Result deduplication

### Common Patterns
```swift
class SearchService: ObservableObject {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    func search(query: String, maxResults: Int = 10) async throws -> [Note] {
        // Simple text search for now
        let results = try await databaseService.searchNotes(query: query, limit: maxResults)

        // TODO: Implement ranking algorithm
        return rankResults(results, query: query)
    }

    private func rankResults(_ notes: [Note], query: String) -> [Note] {
        // Placeholder: Sort by created_at for now
        return notes.sorted { $0.createdAt > $1.createdAt }
    }
}
```

## Error Handling

### Service-Specific Errors
```swift
enum DatabaseError: Error {
    case connectionFailed
    case queryFailed(String)
    case notFound
}

enum OllamaError: Error {
    case requestFailed
    case invalidResponse
    case modelNotFound
    case timeout
}

enum SearchError: Error {
    case invalidQuery
    case noResults
}
```

### Propagation Pattern
```swift
// Services throw errors
func fetchNote(id: Int64) async throws -> Note? {
    guard let note = try db.pluck(...) else {
        throw DatabaseError.notFound
    }
    return note
}

// ViewModels catch and handle
func loadNote(id: Int64) async {
    do {
        note = try await databaseService.fetchNote(id: id)
    } catch DatabaseError.notFound {
        errorMessage = "Note not found"
    } catch {
        errorMessage = "Unexpected error: \(error.localizedDescription)"
    }
}
```

## Testing

### Service Mocking
```swift
protocol DatabaseServiceProtocol {
    func fetchNote(id: Int64) async throws -> Note?
    func searchNotes(query: String, limit: Int) async throws -> [Note]
}

class MockDatabaseService: DatabaseServiceProtocol {
    var mockNotes: [Note] = []

    func fetchNote(id: Int64) async throws -> Note? {
        mockNotes.first { $0.id == id }
    }

    func searchNotes(query: String, limit: Int) async throws -> [Note] {
        mockNotes.filter { $0.content.contains(query) }
    }
}
```

### Integration Tests
```swift
final class DatabaseServiceTests: XCTestCase {
    var service: DatabaseService!

    override func setUp() async throws {
        service = try DatabaseService(path: ":memory:")
        // Insert test data
    }

    func testFetchNote() async throws {
        let note = try await service.fetchNote(id: 1)
        XCTAssertNotNil(note)
        XCTAssertEqual(note?.id, 1)
    }
}
```

## Do NOT

- **NEVER block main thread** - All service methods are async
- **NEVER expose database connection** - Keep private
- **NEVER use global state** - Pass dependencies via init
- **NEVER skip error handling** - All async calls can fail
- **NEVER hardcode URLs** - Use configuration/environment

## Performance Optimization

### Caching Strategy
```swift
actor DatabaseService {
    private var noteCache: [Int64: Note] = [:]

    func fetchNote(id: Int64, useCache: Bool = true) async throws -> Note? {
        if useCache, let cached = noteCache[id] {
            return cached
        }

        guard let note = try await queryDatabase(id: id) else {
            return nil
        }

        noteCache[id] = note
        return note
    }
}
```

### Batch Queries
```swift
// Fetch multiple notes in single query
func fetchNotes(ids: [Int64]) async throws -> [Note] {
    let query = notesTable.filter(ids.contains(id))
    return try db.prepare(query).map { Note(from: $0) }
}
```

## Related Context

@SeleneChat/Sources/Models/Note.swift
@SeleneChat/Tests/ServicesTests/
@database/schema.sql
@SeleneChat/CLAUDE.md
