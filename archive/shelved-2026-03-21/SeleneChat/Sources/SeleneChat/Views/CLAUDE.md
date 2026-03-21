# SeleneChat Views Layer Context

## Purpose

SwiftUI views for SeleneChat macOS app. ADHD-optimized UI for conversational note querying with clickable citations, clean visual hierarchy, and minimal cognitive load.

## Tech Stack

- SwiftUI (declarative UI framework)
- Combine (reactive data binding)
- AppKit integration (macOS-specific features)
- SF Symbols (system icons)

## Key Files

- ContentView.swift - Main app container
- ChatView.swift - Chat interface with messages
- CitationView.swift - Inline citation displays
- NoteDetailView.swift - Full note viewer
- SettingsView.swift - App configuration
- BriefingView.swift - Morning briefing display with action buttons
- Components/ - Reusable UI components

## Architecture

### View Hierarchy
```
ContentView (NavigationSplitView)
├── Sidebar (future)
├── ChatView (primary)
│   ├── MessageRow (user/assistant)
│   │   └── CitationButton (clickable [1])
│   └── InputArea (text field + send)
└── NoteDetailView (detail)
    ├── NoteHeader (metadata)
    ├── NoteContent (markdown)
    └── RelatedNotes (links)
```

### State Management
```swift
@StateObject - View owns ViewModel
@EnvironmentObject - Shared services
@Published - ViewModel properties
@State - Local view state
@Binding - Parent-child data flow
```

## ChatView

### Responsibilities
- Display conversation history
- Capture user input
- Send queries to OllamaService
- Render citations as clickable elements
- Scroll to latest message
- Handle loading states

### Common Patterns
```swift
struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @EnvironmentObject var ollamaService: OllamaService
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            messagesList
            Divider()
            inputArea
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var inputArea: some View {
        HStack {
            TextField("Ask about your notes...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendMessage() }

            Button("Send") { sendMessage() }
                .disabled(inputText.isEmpty || isLoading)
        }
        .padding()
    }

    private func sendMessage() {
        guard !inputText.isEmpty else { return }

        let query = inputText
        inputText = ""
        isLoading = true

        Task {
            await viewModel.sendQuery(query)
            isLoading = false
        }
    }
}
```

## BriefingView

### Responsibilities
- Display LLM-generated morning briefing on app open
- Show loading, content, and error states
- Provide "dig in", "show something else", and "skip" actions
- Transition to ChatView with context preserved

### States
- notLoaded: Triggers loadBriefing() on appear
- loading: Shows ProgressView
- loaded: Shows briefing card with action buttons
- failed: Shows error with retry option

## CitationView

### Responsibilities
- Parse citation markers ([1], [2], etc.)
- Render as clickable buttons
- Navigate to source note on click
- Highlight on hover

### Common Patterns
```swift
struct CitationView: View {
    let text: String
    let onCitationTap: (Int) -> Void

    var body: some View {
        Text(attributedText)
            .environment(\.openURL, OpenURLAction { url in
                if let citationNum = parseCitation(url) {
                    onCitationTap(citationNum)
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributedText: AttributedString {
        var result = AttributedString(text)

        // Find citation patterns [1], [2], etc.
        let pattern = /\[(\d+)\]/
        let matches = text.matches(of: pattern)

        for match in matches {
            let range = match.range
            if let attrRange = result.range(of: text[range]) {
                result[attrRange].link = URL(string: "citation://\(match.1)")
                result[attrRange].foregroundColor = .blue
                result[attrRange].underlineStyle = .single
            }
        }

        return result
    }

    private func parseCitation(_ url: URL) -> Int? {
        guard url.scheme == "citation",
              let num = Int(url.host ?? "") else {
            return nil
        }
        return num
    }
}
```

## MessageRow

### Responsibilities
- Display user vs. assistant messages
- Different styling for each role
- Render citations in assistant messages
- Show timestamps
- Copy message button

### Common Patterns
```swift
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading) {
                Text(message.role == .user ? "You" : "Selene")
                    .font(.caption)
                    .foregroundColor(.secondary)

                messageContent
                    .padding(12)
                    .background(backgroundColor)
                    .cornerRadius(16)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity * 0.7, alignment: message.alignment)

            if message.role == .assistant { Spacer() }
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            CitationView(text: message.content) { citationNum in
                // Navigate to note
            }
        } else {
            Text(message.content)
        }
    }

    private var backgroundColor: Color {
        message.role == .user ? .blue.opacity(0.2) : .gray.opacity(0.1)
    }

    private var alignment: Alignment {
        message.role == .user ? .trailing : .leading
    }
}
```

## ADHD-Optimized UI Patterns

### Visual Hierarchy
```swift
// Clear role distinction
.foregroundColor(role == .user ? .blue : .green)

// Size hierarchy
.font(.title3)    // Main content
.font(.caption)   // Metadata
.font(.caption2)  // Timestamps
```

### Reduced Cognitive Load
```swift
// Loading indicator
if isLoading {
    ProgressView()
        .scaleEffect(0.7)
}

// Empty state guidance
if messages.isEmpty {
    Text("Ask a question about your notes")
        .foregroundColor(.secondary)
        .italic()
}

// Error states
if let error = viewModel.error {
    Label(error, systemImage: "exclamationmark.triangle")
        .foregroundColor(.red)
}
```

### Keyboard Shortcuts
```swift
.keyboardShortcut("n", modifiers: .command)  // New chat
.keyboardShortcut(.return, modifiers: [])    // Send message
.keyboardShortcut("k", modifiers: .command)  // Focus search
```

## Accessibility

### VoiceOver Support
```swift
.accessibilityLabel("Chat message from Selene")
.accessibilityValue(message.content)
.accessibilityHint("Double tap to copy")
```

### Dynamic Type
```swift
.font(.body)  // Respects user size preference
.lineLimit(nil)  // Allows text wrapping
```

### High Contrast
```swift
@Environment(\.colorSchemeContrast) var contrast

var citationColor: Color {
    contrast == .increased ? .blue : .accentColor
}
```

## Testing

### Preview Providers
```swift
#Preview("Chat View - Empty") {
    ChatView()
        .environmentObject(MockOllamaService())
}

#Preview("Chat View - With Messages") {
    let viewModel = ChatViewModel()
    viewModel.messages = ChatMessage.mockMessages
    return ChatView(viewModel: viewModel)
}

#Preview("Dark Mode") {
    ChatView()
        .preferredColorScheme(.dark)
}
```

### UI Tests
```swift
final class ChatViewUITests: XCTestCase {
    func testSendMessage() throws {
        let app = XCUIApplication()
        app.launch()

        let textField = app.textFields["Ask about your notes..."]
        textField.tap()
        textField.typeText("What are my recent notes?")

        app.buttons["Send"].tap()

        XCTAssertTrue(app.staticTexts["What are my recent notes?"].waitForExistence(timeout: 1))
    }
}
```

## Do NOT

- **NEVER block main thread** - Use Task for async operations
- **NEVER force-unwrap in views** - Use optional binding
- **NEVER use fixed sizes** - Respect dynamic type
- **NEVER skip accessibility** - Add labels and hints
- **NEVER ignore dark mode** - Test both themes
- **NEVER use magic numbers** - Define constants for spacing/sizing

## Performance Optimization

### LazyVStack for Long Lists
```swift
// Use LazyVStack for chat messages (renders only visible)
LazyVStack {
    ForEach(messages) { message in
        MessageRow(message: message)
    }
}
```

### Debouncing Input
```swift
@State private var searchText = ""
@State private var debouncedSearch = ""

.onChange(of: searchText) { newValue in
    Task {
        try await Task.sleep(for: .milliseconds(300))
        debouncedSearch = newValue
    }
}
```

### View Identity
```swift
// Stable IDs for smooth animations
ForEach(messages) { message in  // message.id must be stable
    MessageRow(message: message)
        .id(message.id)
}
```

## Related Context

@SeleneChat/Sources/ViewModels/
@SeleneChat/Sources/Services/CLAUDE.md
@SeleneChat/CLAUDE.md
