# Selene Chat - Quick Start Guide

## What You Just Built

Congratulations! You now have a fully functional **Phase 1** native macOS chatbot that can:

- 🔍 **Search** your Selene process notes with natural language
- 🎯 **Filter** by concepts, themes, energy levels, and dates
- 💬 **Chat interface** with conversation history
- 🔒 **Privacy-first** architecture ready for Apple Intelligence & Claude API
- 🧠 **ADHD-optimized** UI with visual indicators (energy, mood, sentiment)

## Running the App

### Method 1: Quick Start

```bash
cd /Users/chaseeasterling/selene/SeleneChat
swift run
```

The app will launch and automatically try to connect to your Selene database at:
`/Users/chaseeasterling/selene/data/selene.db`

### Method 2: Build and Run

```bash
./build.sh
swift run
```

### Method 3: Open in Xcode

```bash
open Package.swift
```

Then press **Cmd+R** to build and run in Xcode.

## First Time Setup

1. **Launch the app**
   - The app should automatically find your Selene database
   - Look for the green "Connected to Selene" indicator in the chat view

2. **If not connected**:
   - Go to **SeleneChat > Settings** (Cmd+,)
   - Click **Browse** next to Database Path
   - Navigate to `/Users/chaseeasterling/selene/data/selene.db`
   - Click **Test Connection**

3. **Verify connection**:
   - Green dot = ✅ Connected
   - Red dot = ❌ Not connected (check path)

## Using the App

### Chat Interface

The chat interface lets you ask questions about your notes:

**Examples:**
- "Show me notes about Docker"
- "Find notes from last week"
- "What did I write about project planning?"
- "Notes where I was in hyperfocus"

**Current Behavior (Phase 1):**
- Searches your database for relevant notes
- Returns matching notes with metadata
- Shows concepts, themes, energy, and mood

**Future (Phase 2 & 3):**
- Apple Intelligence will provide natural responses
- Claude API for project management advice
- Conversational follow-ups

### Search Interface

Click **Search** in the sidebar for advanced filtering:

1. **Text Search**: Type keywords in the search box
2. **Energy Filters**: Toggle high ⚡, medium 🔋, or low 🪫
3. **Concept Chips**: Click concepts to filter (shows top 20)
4. **Theme Chips**: Click themes to filter
5. **Results**: Click any note to view full details

**Pro Tips:**
- Combine filters for precise searches
- Energy filter helps match notes to your current state
- Click "Clear" to reset all filters

### Note Details

When you select a note, you'll see:

- **Full content** (text-selectable for copying)
- **Metadata**: Theme, energy, mood, sentiment
- **Concepts**: AI-extracted key topics
- **Timestamp**: When the note was created

## Current Capabilities

### ✅ Phase 1 - Complete

- [x] Native macOS app (SwiftUI)
- [x] SQLite database integration
- [x] Full-text note search
- [x] Advanced filtering (concepts, themes, energy, dates)
- [x] Chat interface with history
- [x] Note detail view with metadata
- [x] Privacy router architecture
- [x] ADHD-optimized UI

### 🚧 Phase 2 - Next Steps

- [ ] Apple Intelligence integration
- [ ] On-device natural language understanding
- [ ] Private Cloud Compute for complex queries
- [ ] Ollama integration (local LLM)
- [ ] Natural conversation responses

### 📋 Phase 3 - Future

- [ ] Claude API integration
- [ ] Privacy router completion
- [ ] Sanitization pipeline
- [ ] Visual LLM tier indicators
- [ ] Project management features

## Privacy Architecture (Preview)

The app is already built with a three-tier privacy model:

### 🔒 Tier 1: On-Device
- **What**: Apple Intelligence
- **When**: All note content, sensitive topics
- **Privacy**: Nothing leaves your device

### 🔐 Tier 2: Private Cloud
- **What**: Apple Private Cloud Compute
- **When**: Complex queries with sensitive data
- **Privacy**: End-to-end encrypted, no data retention

### 🌐 Tier 3: External
- **What**: Claude API
- **When**: Non-sensitive planning/technical queries
- **Privacy**: No personal note content sent

**Current Status**: Privacy router logic is implemented but LLMs not yet integrated. All queries currently search the local database.

## Troubleshooting

### App won't launch

```bash
# Clean and rebuild
cd /Users/chaseeasterling/selene/SeleneChat
swift package clean
swift build
swift run
```

### Database not connecting

1. Check the database exists:
   ```bash
   ls -lh /Users/chaseeasterling/selene/data/selene.db
   ```

2. Check file permissions:
   ```bash
   chmod 644 /Users/chaseeasterling/selene/data/selene.db
   ```

3. Verify in Settings (Cmd+,) - should show green "Connected"

### No notes showing

1. Verify Selene has processed notes:
   ```bash
   sqlite3 /Users/chaseeasterling/selene/data/selene.db \
     "SELECT COUNT(*) FROM raw_notes;"
   ```

2. If 0, run a test note through Selene first

3. Try clicking "Search" with no filters (should show all notes)

### Search not working

- Make sure database is connected (green indicator)
- Try simpler search terms
- Use concept/theme filters instead of text search
- Check that notes contain your search terms

## Development

### Project Structure

```
SeleneChat/
├── Sources/
│   ├── App/                    # App entry & main view
│   ├── Models/                 # Data structures
│   ├── Services/               # Business logic & database
│   ├── Views/                  # UI components
│   └── Utilities/              # Helpers (empty for now)
├── Package.swift               # Dependencies
├── README.md                   # Full documentation
├── QUICKSTART.md              # This file
└── build.sh                    # Build script
```

### Key Files

- `DatabaseService.swift` - SQLite queries for notes
- `SearchService.swift` - Search & filter logic
- `PrivacyRouter.swift` - LLM routing decisions
- `ChatViewModel.swift` - Chat orchestration
- `ChatView.swift` - Chat UI
- `SearchView.swift` - Search UI

### Adding Features

The codebase is structured for easy extension:

1. **New LLM Integration**: Add service in `Services/`
2. **New UI View**: Add in `Views/`
3. **New Data Model**: Add in `Models/`
4. **New Utility**: Add in `Utilities/`

## Next Steps

### For You:

1. **Test the app** with your existing Selene notes
2. **Try different searches** to see what works well
3. **Explore the chat interface** (Phase 1 returns search results)
4. **Check out the Search view** for advanced filtering

### For Phase 2 Development:

1. **Apple Intelligence SDK**
   - Add App Intents framework
   - Implement Writing Tools API
   - Configure Private Cloud Compute

2. **Ollama Integration**
   - Connect to existing Ollama instance (localhost:11434)
   - Use mistral:7b model (already running in Selene)
   - Implement local query processing

3. **Enhanced Chat**
   - Natural language responses
   - Context-aware answers
   - Follow-up questions

### For Phase 3 Development:

1. **Claude API**
   - Add API key configuration
   - Implement sanitization pipeline
   - Test routing decisions

2. **Advanced Features**
   - Pattern detection visualization
   - Project management assistance
   - Siri integration

## Feedback & Issues

As you use the app, note:
- What works well?
- What's confusing?
- What features would be most valuable?
- Any bugs or errors?

## Resources

- **Selene Database**: `/Users/chaseeasterling/selene/data/selene.db`
- **Obsidian Vault**: `/Users/chaseeasterling/selene/vault/Selene/`
- **Project Code**: `/Users/chaseeasterling/selene/SeleneChat/`

## Summary

You now have a solid **Phase 1** foundation for a privacy-focused, ADHD-optimized chatbot that interfaces with your Selene notes. The architecture is ready for Apple Intelligence and Claude API integration in future phases.

**Enjoy chatting with your notes! 🧠✨**
