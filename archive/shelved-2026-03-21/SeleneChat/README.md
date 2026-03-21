# Selene Chat

A privacy-focused macOS chatbot for interacting with your Selene process notes.

## Features

### Phase 1 - Foundation (Current)

- ✅ Native macOS app built with SwiftUI
- ✅ Direct SQLite database access to Selene notes
- ✅ Advanced search with filters:
  - Full-text search
  - Filter by concepts, themes, energy levels
  - Date range filtering
- ✅ Chat interface with conversation history
- ✅ Privacy-aware routing system (prepares for future LLM integration)
- ✅ Note detail view with metadata (concepts, themes, sentiment, energy)
- ✅ ADHD-optimized UI with visual indicators

## Debug System (Development)

In DEBUG builds, SeleneChat includes a debug system for Claude Code visibility:

### Files
- `/tmp/selenechat-debug.log` - Continuous log of errors and state changes
- `/tmp/selenechat-snapshot.json` - Full app state dump (on request)
- `/tmp/selenechat-last-error` - Timestamp of most recent error

### Triggering a Snapshot
```bash
touch /tmp/selenechat-snapshot-request
sleep 2
cat /tmp/selenechat-snapshot.json
```

### Checking for Errors
```bash
cat /tmp/selenechat-last-error
tail -100 /tmp/selenechat-debug.log
```

See `docs/plans/2026-01-01-selenechat-debug-system-design.md` for full documentation.

## Privacy Model

Selene Chat uses a three-tier privacy system:

1. **🔒 On-Device** (Apple Intelligence)
   - All note content processed locally
   - Nothing leaves your device
   - For sensitive personal content

2. **🔐 Private Cloud** (Apple Private Cloud Compute)
   - Complex queries needing more compute
   - End-to-end encrypted
   - No data retention on Apple servers

3. **🌐 External** (Claude API)
   - Non-sensitive planning/technical queries
   - No personal note content sent
   - For project management, scoping advice

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9 or later
- Access to Selene database (selene.db)

## Installation

### Option 1: Build with Swift Package Manager

```bash
cd SeleneChat
swift build
swift run
```

### Option 2: Open in Xcode

```bash
cd SeleneChat
open Package.swift
```

Then press Cmd+R to build and run.

### Option 3: Generate Xcode Project

```bash
cd SeleneChat
swift package generate-xcodeproj
open SeleneChat.xcodeproj
```

## Configuration

On first launch, configure the database path in Settings:

1. Go to **SeleneChat > Settings** (Cmd+,)
2. Click **Browse** next to Database Path
3. Navigate to `/path/to/selene/data/selene.db`
4. Click **Test Connection** to verify

Default path: `/Users/chaseeasterling/selene/data/selene.db`

## Usage

### Chat Interface

Ask natural language questions about your notes:

- "Show me notes about Docker from last week"
- "Find notes where I was in hyperfocus"
- "What did I write about project planning?"

The app will:
1. Search your Selene database
2. Find relevant notes
3. Display results with full metadata

### Search Interface

Advanced filtering:

1. **Text Search**: Search note titles and content
2. **Energy Filter**: Find notes by energy level (high ⚡, medium 🔋, low 🪫)
3. **Concepts**: Filter by AI-extracted concepts
4. **Themes**: Filter by note themes
5. **Date Range**: Find notes from specific time periods

### Note Details

Click any note to view:
- Full content
- Metadata (theme, energy, mood, sentiment)
- AI-extracted concepts
- Timestamp and source info

## Architecture

```
SeleneChat/
├── Sources/
│   ├── App/                    # App entry point
│   │   ├── SeleneChatApp.swift
│   │   └── ContentView.swift
│   ├── Models/                 # Data models
│   │   ├── Note.swift
│   │   ├── Message.swift
│   │   └── ChatSession.swift
│   ├── Services/               # Business logic
│   │   ├── DatabaseService.swift
│   │   ├── SearchService.swift
│   │   ├── PrivacyRouter.swift
│   │   └── ChatViewModel.swift
│   ├── Views/                  # UI components
│   │   ├── ChatView.swift
│   │   ├── SearchView.swift
│   │   └── SettingsView.swift
│   └── Utilities/              # Helper functions
└── Package.swift               # Dependencies
```

## Database Schema

The app reads from Selene's SQLite database:

### Tables Used

- **raw_notes**: Original note content and metadata
- **processed_notes**: AI-extracted concepts, themes, sentiment
- **sentiment_history**: Emotional tracking and ADHD markers

### Key Fields

- `title`, `content`: Note text
- `concepts`: AI-extracted concepts (JSON array)
- `primary_theme`, `secondary_themes`: Note categorization
- `energy_level`: high/medium/low (ADHD-optimized)
- `emotional_tone`: mood tracking
- `overall_sentiment`: positive/negative/neutral
- `created_at`: Timestamp

## Development Roadmap

### ✅ Phase 1: Foundation (Complete)
- Basic UI and database integration
- Search and filtering
- Note display with metadata

### 🚧 Phase 2: Local Intelligence (Planned)
- Apple Intelligence integration
- On-device natural language understanding
- Private Cloud Compute for complex queries
- Ollama integration for local processing

### 📋 Phase 3: External Integration (Planned)
- Claude API integration for non-sensitive queries
- Privacy router completion
- Sanitization pipeline
- Visual tier indicators

### 🎯 Phase 4: Advanced Features (Future)
- **Chat session summaries to database** - Save chat conversations for history tracking and pattern analysis
- Pattern detection visualization
- Project management assistance
- Siri integration
- Advanced ADHD-optimized features

## Privacy Guarantees

- **Read-Only**: App never modifies your notes
- **Local-First**: All data stays on your device
- **No Tracking**: No analytics or telemetry
- **Open Source**: Code available for audit (when published)

## Troubleshooting

### Database Connection Failed

1. Verify database path in Settings
2. Ensure Selene database exists at specified path
3. Check file permissions (should be readable)
4. Try absolute path instead of relative path

### No Notes Showing

1. Verify Selene has processed notes (check `raw_notes` table)
2. Try refreshing search (click Search button)
3. Clear all filters
4. Check database connection status

### Search Not Working

1. Ensure database is connected (green indicator)
2. Try simpler search terms
3. Check if notes contain the search terms
4. Try using concept or theme filters instead

## Contributing

This is currently a personal project. Future plans may include:
- Open sourcing the codebase
- Community contributions
- Plugin system for extensions

## License

[To be determined]

## Contact

Part of the Selene ecosystem - a local-first, privacy-focused knowledge management system for ADHD minds.
