# SeleneChat Swift Package Context

## Purpose

Three-target Swift package containing SeleneChat (macOS menu bar app), SeleneMobile (iOS app), and SeleneShared (shared library). Provides conversational interface with Ollama LLM and clickable citations for source notes. ADHD-optimized for quick note retrieval and visual knowledge exploration.

## Three-Target Structure

```
Package.swift
├── SeleneShared (library)     # Shared models, protocols, utilities
│   ├── Models/                # Note, Thread, ChatSession, Message, etc.
│   ├── Protocols/             # DataProvider, LLMProvider
│   └── Services/              # QueryAnalyzer, ContextBuilder, PrivacyRouter, etc.
├── SeleneChat (macOS)         # Menu bar app, direct SQLite + Ollama
│   ├── Services/              # DatabaseService, OllamaService, ChatViewModel
│   ├── Views/                 # ChatView, BriefingView, ThreadWorkspaceView
│   └── depends on: SeleneShared, SQLite.swift
├── SeleneMobile (iOS)         # iOS app, REST API via Tailscale
│   ├── Services/              # RemoteDataService, RemoteOllamaService, ConnectionManager
│   ├── Views/                 # MobileChatView, MobileThreadsView, MobileBriefingView
│   ├── Activities/            # Live Activities (ActivityKit)
│   └── depends on: SeleneShared only
└── SeleneChatTests            # Tests for SeleneChat + SeleneShared
```

**Key design:** macOS uses `DatabaseService` (direct SQLite) + `OllamaService` (direct HTTP). iOS uses `RemoteDataService` + `RemoteOllamaService` (both via Fastify REST API over Tailscale). Both conform to shared `DataProvider` and `LLMProvider` protocols from SeleneShared.

## Tech Stack

- **Swift** 5.9+ (SwiftUI framework)
- **SQLite.swift** - Swift wrapper for SQLite database (macOS only)
- **Ollama** - Local LLM integration (mistral:7b)
- **Swift Package Manager** - Dependency management
- **ActivityKit** - Live Activities (iOS only)
- **XCTest** - Testing framework

## Key Files

- Package.swift - Swift package manifest (3 targets)
- Sources/SeleneShared/Protocols/DataProvider.swift - Data access protocol (29 methods)
- Sources/SeleneShared/Protocols/LLMProvider.swift - LLM access protocol
- Sources/SeleneChat/App/SeleneChatApp.swift - macOS app entry point
- Sources/SeleneChat/Services/DatabaseService.swift - SQLite (implements DataProvider)
- Sources/SeleneChat/Services/OllamaService.swift - Ollama HTTP (implements LLMProvider)
- Sources/SeleneChat/Services/ChatViewModel.swift - macOS chat logic
- Sources/SeleneMobile/App/SeleneMobileApp.swift - iOS app entry point
- Sources/SeleneMobile/Services/RemoteDataService.swift - REST client (implements DataProvider)
- Sources/SeleneMobile/Services/RemoteOllamaService.swift - LLM proxy (implements LLMProvider)
- Sources/SeleneMobile/Services/MobileChatViewModel.swift - iOS chat logic
- Sources/SeleneMobile/Services/ConnectionManager.swift - Tailscale connection management
- Tests/ - Unit and integration tests
- Sources/SeleneChat/Debug/ - Debug logging and snapshot system (DEBUG builds only)

## Architecture

### MVVM Pattern
```
Views (SwiftUI)
  ↓
ViewModels (@Published state)
  ↓
Services (Business logic)
  ↓
Models (Data structures)
  ↓
SQLite Database
```

### Key Services
- **DatabaseService** - SQLite connection and queries
- **SearchService** - Note search with relevance ranking
- **OllamaService** - LLM communication and response parsing
- **CitationService** - Extract and link source notes

## Data Flow

1. **User Types Query** - ChatView captures input
2. **Search Notes** - SearchService finds relevant notes
3. **Generate Context** - Combine query + retrieved notes
4. **Call Ollama** - OllamaService sends prompt with context
5. **Parse Response** - Extract answer + citation markers [1], [2]
6. **Display with Citations** - ChatView shows answer with clickable citations
7. **Navigate to Source** - Click citation → DetailView shows full note

## Common Patterns

### SwiftUI View Structure
```swift
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()

    var body: some View {
        VStack {
            messagesList
            inputArea
        }
        .onAppear { viewModel.loadInitialData() }
    }
}
```

### Async/Await for LLM Calls
```swift
func sendQuery(_ query: String) async {
    do {
        let response = try await ollamaService.generateResponse(
            query: query,
            context: relevantNotes
        )
        await MainActor.run {
            messages.append(response)
        }
    } catch {
        // Handle error
    }
}
```

### Database Queries with SQLite.swift
```swift
import SQLite

let db = try Connection(dbPath)
let notesTable = Table("raw_notes")
let id = Expression<Int64>("id")
let content = Expression<String>("content")

let results = try db.prepare(
    notesTable.filter(content.like("%\(query)%"))
).map { Note(from: $0) }
```

## Testing

### Standard Practice: CLI Tests Over Manual Testing

**Always prefer automated CLI tests over manual app testing.** This enables:
- Verification without launching the app
- Tests run against test database (no production data risk)
- Reproducible, documented test cases
- CI/CD compatibility

When implementing a feature, write integration tests that simulate the app flow:
```swift
// Example: Test conversation memory without needing Ollama
func testPromptIncludesConversationHistory() {
    var session = ChatSession()
    session.addMessage(Message(role: .user, content: "Question 1", llmTier: .local))
    session.addMessage(Message(role: .assistant, content: "Answer 1", llmTier: .local))
    session.addMessage(Message(role: .user, content: "Follow-up", llmTier: .local))

    // Simulate ChatViewModel flow
    let priorMessages = Array(session.messages.dropLast())
    let context = SessionContext(messages: priorMessages)

    XCTAssertTrue(context.formattedHistory.contains("Question 1"))
}
```

### Run Tests
```bash
cd SeleneChat
swift test                                    # All tests
swift test --filter SessionContextTests       # Specific test class
swift test --filter ConversationMemory        # Pattern match
```

### Test Organization
- `Tests/SeleneChatTests/Models/` - Unit tests for data models
- `Tests/SeleneChatTests/Services/` - Unit tests for services
- `Tests/SeleneChatTests/Integration/` - Integration tests (cross-component)

### Test Coverage Areas
- DatabaseService - CRUD operations
- SearchService - Relevance ranking
- OllamaService - LLM integration
- Citation parsing - Extract [1], [2] markers
- View models - State management
- SessionContext - Conversation memory (Integration/)
- BriefingState - Briefing status state machine
- BriefingGenerator - Prompt building and response parsing
- BriefingViewModel - State management and actions
- BriefingIntegration - End-to-end briefing flow
- QueryAnalyzerDeepDive - Deep-dive intent detection
- DeepDivePromptBuilder - Prompt construction
- ActionExtractor - Action parsing
- ActionService - Action capture
- DeepDiveIntegration - End-to-end flow
- QueryAnalyzerSynthesis - Synthesis intent detection
- SynthesisPromptBuilder - Prompt construction
- SynthesisIntegration - End-to-end flow

## ADHD-Optimized Features

### Visual Design
- **Clean interface** - Minimal distractions
- **Clear hierarchy** - Chat > Citations > Details
- **Color coding** - User vs. AI messages distinct

### Cognitive Load Reduction
- **Instant search** - No loading delays
- **Clickable citations** - Direct source access
- **Session summaries** - Review conversation context
- **Keyboard shortcuts** - Fast navigation

### Context Preservation
- **Chat history** - Review previous queries
- **Citation links** - Always traceable to source
- **Related notes** - Discover connections

## Do NOT

- **NEVER block main thread** - Use async/await for I/O
- **NEVER force-unwrap optionals** - Use guard/if let
- **NEVER expose database connection** - Encapsulate in Service
- **NEVER hardcode database path** - Use environment or config
- **NEVER skip error handling** - All service calls can fail

## Build and Run

### Auto-Build on Commit (Recommended)
Commits that touch SeleneChat files automatically trigger a rebuild and install to `/Applications/SeleneChat.app` via the `post-commit` git hook. A macOS notification confirms success/failure.

This is the standard workflow - just commit your changes and the production app updates automatically.

### Manual Build & Install
```bash
cd SeleneChat
./build-app.sh                              # Build .app bundle
cp -R .build/release/SeleneChat.app /Applications/  # Install
```

### Development (CLI - uses test database)
```bash
cd SeleneChat
swift build
swift run
```
Note: CLI builds use `~/selene/data-test/selene-test.db`, not production data.

### Release (CLI)
```bash
swift build -c release
.build/release/SeleneChat
```

### Xcode
```bash
swift package generate-xcodeproj
open SeleneChat.xcodeproj
```

### Database Selection
- **CLI binary** → test database (`~/selene/data-test/selene-test.db`)
- **.app bundle** → production database (`~/selene-data/selene.db`)

Detection is automatic via `isRunningFromAppBundle()` in DatabaseService.

## Related Context

@SeleneChat/README.md
@SeleneChat/Sources/Services/CLAUDE.md
@SeleneChat/Sources/Views/CLAUDE.md
@database/schema.sql
@README.md
