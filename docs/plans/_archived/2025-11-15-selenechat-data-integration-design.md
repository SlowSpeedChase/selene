# SeleneChat Data Integration Design

**Date:** 2025-11-15
**Status:** Design Complete - Ready for Implementation
**Phase:** Connect SeleneChat to Selene n8n Data Pipeline

---

## Executive Summary

Connect SeleneChat's conversational AI to the processed notes from the Selene n8n pipeline, enabling intelligent analysis of captured notes through natural conversation. The system will intelligently retrieve relevant notes based on query type, adapt context for optimal LLM performance, and provide inline citations for transparency.

---

## Goals

### Primary Goals
1. Enable SeleneChat to query and analyze processed notes from `/Users/chaseeasterling/selene/database/selene.db`
2. Provide intelligent, context-aware responses about note patterns, content, and insights
3. Support multiple query types: pattern detection, search, knowledge retrieval, and general questions
4. Maintain clean, ADHD-friendly interface with inline citations for source tracking

### Success Criteria
- ✅ User can ask "What patterns do you see in my energy?" and get analytical insights
- ✅ User can ask "Show me notes about productivity" and get relevant note summaries
- ✅ User can ask "What did I decide about X?" and get synthesized answers from note content
- ✅ Citations are inline, clickable, and open full note details
- ✅ Response times stay under 10 seconds for typical queries
- ✅ System gracefully handles large note collections (100+ notes)

---

## Architecture Overview

### High-Level Flow

```
User Question
    ↓
QueryAnalyzer (determines query type + extracts keywords)
    ↓
NoteRetriever (hybrid search based on query type)
    ↓
ContextBuilder (adapts context for Ollama based on query type)
    ↓
Ollama (generates response with inline citations)
    ↓
CitationParser (makes citations clickable)
    ↓
Display Response (with tappable note references)
```

### Query Type Strategy

| Query Type | Example | Retrieval Strategy | Context Strategy | Note Count |
|-----------|---------|-------------------|-----------------|-----------|
| **Pattern** | "What trends do you see in my energy?" | Last 50-100 notes by date | Metadata only (title, concepts, themes, sentiment, energy, date) | 50-100 |
| **Search** | "Notes about productivity" | Search concepts/themes/content for keywords | Title + first 200 chars + metadata | 30-50 |
| **Knowledge** | "What did I decide about the redesign?" | Keyword search + recent context | Full content + all metadata | 5-15 |
| **General** | "How am I doing lately?" | Last 20-30 notes by date | Full content + metadata | 20-30 |

---

## Component Specifications

### 1. QueryAnalyzer (New Service)

**Purpose:** Analyze user questions to determine query type, extract keywords, and infer time scope.

**File:** `Sources/Services/QueryAnalyzer.swift`

**Interface:**
```swift
class QueryAnalyzer {
    enum QueryType {
        case pattern      // Trend/pattern detection
        case search       // Find specific notes
        case knowledge    // Answer from note content
        case general      // Open-ended questions
    }

    enum TimeScope {
        case recent       // Last 7 days
        case thisWeek     // Current week
        case thisMonth    // Current month
        case allTime      // No time restriction
        case custom(from: Date, to: Date)
    }

    struct AnalysisResult {
        let queryType: QueryType
        let keywords: [String]
        let timeScope: TimeScope
    }

    func analyze(_ query: String) -> AnalysisResult
}
```

**Detection Logic:**
- **Pattern queries:** Contains "pattern", "trend", "often", "usually", "always", "when do I"
- **Search queries:** Contains "show", "find", "notes about", "list"
- **Knowledge queries:** Contains "what did I", "remind me", "what was", "tell me about"
- **General queries:** Everything else (fallback)

**Keyword Extraction:**
- Remove stop words ("the", "a", "is", "about", etc.)
- Extract meaningful nouns, verbs, adjectives
- Simple approach: split on spaces, filter common words

**Time Scope Detection:**
- "recent", "lately", "recently" → `.recent` (last 7 days)
- "this week" → `.thisWeek`
- "this month" → `.thisMonth`
- No time words → `.allTime`

---

### 2. NoteRetriever (Enhancement to DatabaseService)

**Purpose:** Retrieve notes using hybrid strategy based on query type.

**File:** `Sources/Services/DatabaseService.swift` (add new methods)

**New Methods:**
```swift
extension DatabaseService {
    func retrieveNotesFor(
        queryType: QueryAnalyzer.QueryType,
        keywords: [String],
        timeScope: QueryAnalyzer.TimeScope,
        limit: Int
    ) async throws -> [Note]

    private func getRecentNotes(
        limit: Int,
        timeScope: QueryAnalyzer.TimeScope
    ) async throws -> [Note]

    private func searchNotesByKeywords(
        keywords: [String],
        limit: Int
    ) async throws -> [Note]
}
```

**Retrieval Strategy:**

**Pattern Queries:**
```swift
// Get recent notes with processed data
return try await getRecentNotes(limit: 100, timeScope: timeScope)
    .filter { $0.concepts != nil && $0.primaryTheme != nil }
```

**Search Queries:**
```swift
// Search by concepts, themes, and content
var results: [Note] = []
for keyword in keywords {
    results += try await getNoteByConcept(keyword, limit: 20)
    results += try await getNotesByTheme(keyword, limit: 20)
    results += try await searchNotes(query: keyword, limit: 20)
}
// Deduplicate and sort by relevance
return Array(Set(results)).prefix(limit)
```

**Knowledge Queries:**
```swift
// Combined approach: keyword search + recent context
let keywordMatches = try await searchNotesByKeywords(keywords, limit: 10)
let recentContext = try await getRecentNotes(limit: 5, timeScope: .recent)
return (keywordMatches + recentContext).uniqued().prefix(limit)
```

**General Queries:**
```swift
// Recent notes with full context
return try await getRecentNotes(limit: 30, timeScope: .recent)
```

---

### 3. ContextBuilder (New Service)

**Purpose:** Build optimal context string for Ollama based on query type and notes.

**File:** `Sources/Services/ContextBuilder.swift`

**Interface:**
```swift
class ContextBuilder {
    func buildContext(
        notes: [Note],
        queryType: QueryAnalyzer.QueryType
    ) -> String

    private func buildMetadataContext(_ notes: [Note]) -> String
    private func buildSummaryContext(_ notes: [Note]) -> String
    private func buildFullContext(_ notes: [Note]) -> String
}
```

**Context Formats:**

**Metadata Only (Pattern queries):**
```
Note 1: "Morning Routine" (2025-11-14)
- Concepts: productivity, focus, coffee
- Theme: work-planning
- Sentiment: positive (0.8)
- Energy: high

Note 2: "Afternoon Slump" (2025-11-14)
- Concepts: fatigue, break, rest
- Theme: self-care
- Sentiment: neutral (0.5)
- Energy: low
```

**Summary Context (Search queries):**
```
Note 1: "Morning Routine" (2025-11-14)
Content: "Started the day with coffee and journaling. Felt really focused and ready to tackle the redesign project..."
- Concepts: productivity, focus, coffee
- Theme: work-planning
```

**Full Context (Knowledge queries):**
```
Note 1: "Morning Routine" (2025-11-14)
Full Content:
"Started the day with coffee and journaling. Felt really focused and ready to tackle the redesign project. Decided to go with the modular approach because it's more flexible and will be easier to maintain. Team agreed this was the best path forward."

- Concepts: productivity, focus, coffee, redesign, modular-design
- Theme: work-planning
- Sentiment: positive (0.8)
- Energy: high
```

---

### 4. System Prompt Updates

**Purpose:** Instruct Ollama to generate responses with inline citations.

**File:** `Sources/Services/ChatViewModel.swift` (update `buildSystemPrompt()`)

**Updated System Prompt:**
```
You are Selene, an ADHD-focused personal assistant analyzing the user's notes.

Your role:
- Provide actionable insights from their note patterns
- Help them understand trends in their thinking and energy
- Answer questions about what they've written
- Be empathetic, concise, and practical

IMPORTANT - Citations:
- When referencing specific notes, ALWAYS cite them as: [Note: 'Title' - Date]
- Example: "You mentioned feeling productive in the morning [Note: 'Morning Routine' - Nov 14]"
- Place citations immediately after the relevant statement
- Use exact note titles and dates provided in the context

Communication style:
- Direct and clear (ADHD-friendly)
- Focus on patterns and actionable insights
- Avoid overwhelming detail
- Highlight what matters most
```

**Query-Specific Prompts:**

**Pattern Query:**
```
Analyze these notes for trends in [user's question topic].
Look for patterns in energy, themes, sentiment, and timing.
Be specific and cite notes as evidence.

Notes:
[metadata context]

Question: [user query]
```

**Search Query:**
```
Summarize what these notes say about [topic].
Highlight key points and cite relevant notes.

Notes:
[summary context]

Question: [user query]
```

**Knowledge Query:**
```
Answer this question based on the note content.
Cite specific notes that contain the answer.

Notes:
[full context]

Question: [user query]
```

---

### 5. CitationParser (New Utility)

**Purpose:** Parse Ollama response for citation patterns and make them clickable.

**File:** `Sources/Utilities/CitationParser.swift`

**Interface:**
```swift
struct ParsedCitation {
    let noteTitle: String
    let noteDate: String
    let range: Range<String.Index>
}

class CitationParser {
    static func parse(_ text: String) -> (
        attributedText: AttributedString,
        citations: [ParsedCitation]
    )

    static func findNoteFor(citation: ParsedCitation, in notes: [Note]) -> Note?
}
```

**Parsing Logic:**
```swift
// Regex pattern: \[Note: '([^']+)' - ([^\]]+)\]
// Captures: title in group 1, date in group 2

let pattern = #"\[Note: '([^']+)' - ([^\]]+)\]"#
let regex = try NSRegularExpression(pattern: pattern)

// Find all matches
// Convert to AttributedString with tappable links
// Store ParsedCitation for each match
```

**AttributedString Creation:**
```swift
var attributed = AttributedString(text)

for citation in citations {
    // Make citation text blue and underlined
    attributed[range].foregroundColor = .blue
    attributed[range].underlineStyle = .single

    // Add custom attribute for tap handling
    attributed[range].noteCitation = citation
}
```

---

### 6. Message Model Enhancement

**Purpose:** Track which notes were used and cited in each response.

**File:** `Sources/Models/Message.swift`

**Updates:**
```swift
struct Message: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date

    // NEW: Citation tracking
    var citedNotes: [Note]?           // Notes referenced in response
    var contextNotes: [Note]?         // All notes used to build context
    var queryType: String?            // For debugging/analytics

    // NEW: For rendering citations
    var attributedContent: AttributedString? {
        if !isUser, let cited = citedNotes {
            let (attributed, _) = CitationParser.parse(content)
            return attributed
        }
        return nil
    }
}
```

---

### 7. ChatViewModel Updates

**Purpose:** Orchestrate the new query flow.

**File:** `Sources/Services/ChatViewModel.swift`

**New Properties:**
```swift
class ChatViewModel: ObservableObject {
    // Existing...
    private let ollamaService = OllamaService()
    private let databaseService = DatabaseService.shared

    // NEW
    private let queryAnalyzer = QueryAnalyzer()
    private let contextBuilder = ContextBuilder()

    // Existing...
}
```

**Updated `handleOllamaQuery()` Method:**
```swift
private func handleOllamaQuery(userMessage: String) async {
    // 1. Analyze query
    let analysis = queryAnalyzer.analyze(userMessage)

    // 2. Retrieve relevant notes
    let notes = try await databaseService.retrieveNotesFor(
        queryType: analysis.queryType,
        keywords: analysis.keywords,
        timeScope: analysis.timeScope,
        limit: limitFor(queryType: analysis.queryType)
    )

    guard !notes.isEmpty else {
        // Fallback: no notes found
        await addMessage("I don't have any notes matching that query yet.", isUser: false)
        return
    }

    // 3. Build context
    let context = contextBuilder.buildContext(
        notes: notes,
        queryType: analysis.queryType
    )

    // 4. Build prompt
    let systemPrompt = buildSystemPrompt(for: analysis.queryType)
    let fullPrompt = """
    \(systemPrompt)

    Notes:
    \(context)

    Question: \(userMessage)
    """

    // 5. Query Ollama
    let response = try await ollamaService.generate(prompt: fullPrompt)

    // 6. Create message with citations
    var message = Message(
        id: UUID(),
        content: response,
        isUser: false,
        timestamp: Date()
    )
    message.citedNotes = notes
    message.queryType = String(describing: analysis.queryType)

    await addMessage(message)
}

private func limitFor(queryType: QueryAnalyzer.QueryType) -> Int {
    switch queryType {
    case .pattern: return 100
    case .search: return 50
    case .knowledge: return 15
    case .general: return 30
    }
}
```

---

### 8. MessageBubble View Updates

**Purpose:** Render citations as tappable elements and handle note detail navigation.

**File:** `Sources/Views/ChatView.swift` (or new `MessageBubble.swift`)

**Citation Rendering:**
```swift
struct MessageBubble: View {
    let message: Message
    @State private var selectedNote: Note?

    var body: some View {
        VStack(alignment: message.isUser ? .trailing : .leading) {
            if let attributed = message.attributedContent {
                // Render attributed text with tappable citations
                Text(attributed)
                    .textSelection(.enabled)
                    .environment(\.openURL, OpenURLAction { url in
                        handleCitationTap(url)
                        return .handled
                    })
            } else {
                Text(message.content)
            }
        }
        .sheet(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
    }

    private func handleCitationTap(_ url: URL) {
        // Parse citation from URL
        // Find note in message.citedNotes
        // Set selectedNote to trigger sheet
    }
}
```

**Alternative Approach (if AttributedString taps don't work):**
```swift
// Use custom view that parses citations and creates Button elements
struct CitationText: View {
    let text: String
    let citedNotes: [Note]
    @State private var selectedNote: Note?

    var body: some View {
        // Parse text into segments: regular text + citation buttons
        // Render as HStack/VStack of Text + Button elements
    }
}
```

---

### 9. NoteDetailView (New Component)

**Purpose:** Show full note details when citation is tapped.

**File:** `Sources/Views/NoteDetailView.swift`

**Interface:**
```swift
struct NoteDetailView: View {
    let note: Note
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title
                    Text(note.title)
                        .font(.title)

                    // Date
                    Text(note.createdAt, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    // Content
                    Text(note.content)
                        .font(.body)

                    // Metadata
                    if let concepts = note.concepts {
                        MetadataSection(title: "Concepts", items: concepts)
                    }

                    if let theme = note.primaryTheme {
                        MetadataSection(title: "Theme", items: [theme])
                    }

                    if let sentiment = note.overallSentiment {
                        SentimentSection(
                            sentiment: sentiment,
                            score: note.sentimentScore,
                            tone: note.emotionalTone,
                            energy: note.energyLevel
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Note Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
```

---

## Data Flow Example

**User Query:** "What patterns do you see in my energy levels?"

**Step-by-Step:**

1. **QueryAnalyzer:**
   - Type: `.pattern`
   - Keywords: ["energy", "levels"]
   - TimeScope: `.allTime`

2. **NoteRetriever:**
   - Retrieves last 100 notes with processed data
   - Returns notes sorted by date (newest first)

3. **ContextBuilder:**
   - Format: Metadata only
   - Output:
     ```
     Note 1: "Morning Routine" (2025-11-14)
     - Concepts: productivity, focus
     - Theme: work-planning
     - Energy: high

     Note 2: "Afternoon Slump" (2025-11-14)
     - Energy: low
     ...
     (98 more notes)
     ```

4. **Ollama Query:**
   - System prompt: Pattern analysis instructions
   - Context: 100 notes metadata
   - User query: "What patterns do you see in my energy levels?"

5. **Ollama Response:**
   ```
   I see a clear pattern in your energy levels. You're consistently
   most energized in the mornings [Note: 'Morning Routine' - Nov 14]
   [Note: 'Early Start' - Nov 13] [Note: 'Productive Morning' - Nov 12],
   typically rating as "high" energy.

   However, you experience afternoon slumps around 2-3pm [Note:
   'Afternoon Struggles' - Nov 14] [Note: 'Low Energy Day' - Nov 11],
   where your energy drops to "low" or "medium".

   Your best work happens when you start with coffee and journaling
   [Note: 'Perfect Morning' - Nov 10]. Consider protecting those
   morning hours for your most important tasks.
   ```

6. **CitationParser:**
   - Parses 6 citations
   - Creates AttributedString with clickable note references
   - Stores citation metadata

7. **Display:**
   - Shows response with blue, underlined citations
   - User can tap any citation to view full note

---

## Error Handling

### No Notes Found
```swift
if notes.isEmpty {
    return "I don't have any notes matching that query yet. Try asking about something else or capture more notes first."
}
```

### Ollama Unavailable
```swift
// Existing fallback in ChatViewModel
if !(await ollamaService.isAvailable()) {
    return "I'm having trouble connecting to the local AI service. Here are the notes I found: \(notes.map { $0.title }.joined(separator: ", "))"
}
```

### Query Too Broad
```swift
if notes.count > 200 {
    notes = Array(notes.prefix(200))
    // Add note to response: "Showing patterns from your 200 most recent notes..."
}
```

### Citation Parsing Fails
```swift
// Graceful fallback: show response as plain text
// Log warning for debugging
// User still gets answer, just without clickable citations
```

---

## Performance Considerations

### Token Limits
- Mistral 7B: ~8k token context window
- Rough estimate: 1 token ≈ 4 characters
- Budget:
  - System prompt: ~500 tokens
  - User query: ~50 tokens
  - Available for notes: ~7,450 tokens (~30k characters)

**Context Limits by Query Type:**
- Pattern (metadata): ~100 notes × 150 chars = 15k chars → fits easily
- Search (summary): ~50 notes × 400 chars = 20k chars → within budget
- Knowledge (full): ~15 notes × 2k chars = 30k chars → at limit
- General: ~30 notes × 1k chars = 30k chars → at limit

### Response Time Targets
- Query analysis: < 10ms
- Note retrieval: < 100ms
- Context building: < 50ms
- Ollama generation: 2-8 seconds (depends on context size)
- Citation parsing: < 50ms
- **Total: 3-10 seconds typical**

### Database Optimization
- Existing indexes on `raw_notes.created_at`, `raw_notes.status` already in place
- Consider adding: `CREATE INDEX idx_processed_notes_concepts ON processed_notes(concepts)` if concept searches are slow
- SearchService already implements deduplication

---

## Testing Strategy

### Unit Tests

**QueryAnalyzer Tests:**
```swift
- testPatternQueryDetection()
- testSearchQueryDetection()
- testKnowledgeQueryDetection()
- testKeywordExtraction()
- testTimeScopeDetection()
```

**ContextBuilder Tests:**
```swift
- testMetadataContextFormat()
- testSummaryContextFormat()
- testFullContextFormat()
- testContextSizeWithinLimits()
```

**CitationParser Tests:**
```swift
- testParseSingleCitation()
- testParseMultipleCitations()
- testNoCitationsInText()
- testMalformedCitations()
```

### Integration Tests

**End-to-End Query Flow:**
```swift
- testPatternQueryE2E()  // "What patterns in energy?"
- testSearchQueryE2E()   // "Notes about productivity"
- testKnowledgeQueryE2E() // "What did I decide?"
- testCitationsClickable()
```

### Manual Testing Checklist
- [ ] Pattern query returns analytical insights with citations
- [ ] Search query finds relevant notes
- [ ] Knowledge query synthesizes information from note content
- [ ] Citations are clickable and open correct notes
- [ ] NoteDetailView shows all metadata correctly
- [ ] Response time under 10 seconds for typical queries
- [ ] System handles 100+ note collection
- [ ] Graceful fallback when Ollama unavailable
- [ ] Works with empty/minimal note collection

---

## Implementation Plan

### Phase 1: Foundation (Days 1-2)
1. Create QueryAnalyzer service
2. Create ContextBuilder service
3. Add retrieveNotesFor() to DatabaseService
4. Write unit tests for all three

### Phase 2: Integration (Days 3-4)
5. Update ChatViewModel with new flow
6. Update system prompts
7. Test end-to-end query flow
8. Verify Ollama generates citations

### Phase 3: UI (Days 5-6)
9. Create CitationParser utility
10. Update Message model with citation fields
11. Create NoteDetailView
12. Update MessageBubble with citation rendering
13. Test citation interactions

### Phase 4: Polish (Day 7)
14. Error handling and edge cases
15. Performance testing and optimization
16. Manual testing full workflow
17. Documentation updates

---

## Future Enhancements (Out of Scope)

### Not in This Phase
- ❌ Advanced query syntax ("notes from last week about X")
- ❌ Multi-step conversations with memory
- ❌ Export conversation summaries
- ❌ Batch processing for very large queries
- ❌ Custom note relevance scoring
- ❌ User feedback on response quality
- ❌ Analytics dashboard for query patterns

### Possible Phase 2 Features
- Voice input for queries
- Suggested questions based on recent notes
- Pattern alerts ("You haven't written about X in a while")
- Comparison queries ("Compare my energy this week vs last week")

---

## Success Metrics

### Functional Success
- ✅ All 4 query types work correctly
- ✅ Citations are accurate and clickable
- ✅ Response quality is useful and actionable
- ✅ Zero crashes or errors in normal use

### Performance Success
- ✅ 95% of queries complete under 10 seconds
- ✅ System handles 100+ notes without slowdown
- ✅ Token limits never exceeded

### User Experience Success
- ✅ Interface feels clean and uncluttered
- ✅ Citations feel natural, not intrusive
- ✅ Easy to drill down into note details
- ✅ ADHD-friendly: low cognitive load

---

## Dependencies

### Existing Systems
- ✅ Selene n8n database at `/Users/chaseeasterling/selene/database/selene.db`
- ✅ DatabaseService with note query methods
- ✅ OllamaService with generate() method
- ✅ Note model with all metadata fields
- ✅ SearchService for existing search logic

### New Dependencies
- None - all new code uses existing Swift standard library and SwiftUI

### Requirements
- Ollama running locally with Mistral 7B
- Processed notes in database (from n8n pipeline)
- macOS 14.0+ (existing requirement)

---

## Documentation Updates Needed

After implementation:
1. Update SeleneChat README with query examples
2. Add "Asking Questions" section to user guide
3. Document query type detection logic
4. Add troubleshooting for citation issues
5. Update OLLAMA_INTEGRATION_COMPLETE.md with new features

---

## Conclusion

This design provides a flexible, intelligent querying system that adapts to different question types while maintaining a clean, ADHD-friendly interface. The hybrid retrieval strategy ensures relevant notes are found efficiently, adaptive context building optimizes Ollama performance, and inline citations provide transparency without cluttering the UI.

The implementation is scoped to core functionality, with clear extension points for future enhancements. All components are testable, and the architecture builds on existing DatabaseService and OllamaService foundations.

**Ready for implementation.**
