# System Architecture Overview

**Version:** 1.0.0
**Last Updated:** October 30, 2025

## Table of Contents

- [Introduction](#introduction)
- [High-Level Architecture](#high-level-architecture)
- [System Components](#system-components)
- [Data Flow](#data-flow)
- [Technology Stack](#technology-stack)
- [Deployment Architecture](#deployment-architecture)
- [Security & Privacy](#security--privacy)
- [Performance Characteristics](#performance-characteristics)
- [Design Principles](#design-principles)

---

## Introduction

Selene is a knowledge management system built on n8n workflows that processes personal notes using local AI. The system is designed specifically for ADHD minds, automating the tedious parts of knowledge organization while maintaining complete privacy through local-only processing.

**Core Philosophy:**
- **Visual First**: See your entire processing pipeline in n8n's visual editor
- **Privacy First**: All data stays on your machine (no cloud services)
- **ADHD-Friendly**: Automatic organization without manual tagging
- **Modular**: Six independent workflows that can be enabled/disabled as needed

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        INPUT LAYER                               │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐        ┌──────────────┐      ┌─────────────┐│
│  │  Drafts App  │───────▶│  Webhook API │◀─────│  Other Apps ││
│  │  (iOS/Mac)   │  HTTP  │ /api/drafts  │ HTTP │  (Future)   ││
│  └──────────────┘        └──────┬───────┘      └─────────────┘│
│                                  │                               │
└──────────────────────────────────┼───────────────────────────────┘
                                   │
┌──────────────────────────────────┼───────────────────────────────┐
│                    PROCESSING LAYER (n8n)                        │
├──────────────────────────────────┼───────────────────────────────┤
│                                  ▼                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Workflow 01: Ingestion                                    │  │
│  │ • Webhook Trigger                                         │  │
│  │ • Duplicate Detection (content hash)                      │  │
│  │ • Store in raw_notes table                                │  │
│  │ • Status: pending                                         │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                  │                                │
│                                  ▼                                │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │ Workflow 02: LLM Processing (every 30s)                   │  │
│  │ • Poll for pending notes                                  │  │
│  │ • Send to Ollama for analysis                             │  │
│  │ • Extract 3-5 key concepts                                │  │
│  │ • Identify primary + secondary themes                     │  │
│  │ • Store in processed_notes table                          │  │
│  │ • Update status: processed                                │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                  │                                │
│                    ┌─────────────┴──────────────┐               │
│                    ▼                             ▼                │
│  ┌─────────────────────────────┐  ┌──────────────────────────┐  │
│  │ Workflow 05: Sentiment      │  │ Workflow 06: Connections │  │
│  │ Analysis (every 45s)        │  │ Network (every 6h)       │  │
│  │                             │  │                          │  │
│  │ • Analyze emotional tone    │  │ • Calculate note         │  │
│  │ • Detect ADHD markers       │  │   relationships          │  │
│  │ • Track energy levels       │  │ • Find concept overlaps  │  │
│  │ • Store in sentiment_       │  │ • Store in network_      │  │
│  │   history table             │  │   analysis_history       │  │
│  └─────────────────────────────┘  └──────────────────────────┘  │
│                                  │                                │
│                    ┌─────────────┴──────────────┐               │
│                    ▼                             ▼                │
│  ┌─────────────────────────────┐  ┌──────────────────────────┐  │
│  │ Workflow 03: Pattern        │  │ Workflow 04: Obsidian    │  │
│  │ Detection (daily @ 6am)     │  │ Export (daily @ 7am)     │  │
│  │                             │  │                          │  │
│  │ • Analyze theme trends      │  │ • Export processed notes │  │
│  │ • Detect rising/falling     │  │ • Create markdown files  │  │
│  │   patterns                  │  │ • Generate backlinks     │  │
│  │ • Generate insights         │  │ • Organize by theme      │  │
│  │ • Store in detected_        │  │ • Update export status   │  │
│  │   patterns table            │  │                          │  │
│  └─────────────────────────────┘  └──────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
                           │                      │
┌──────────────────────────┼──────────────────────┼────────────────┐
│                  DATA LAYER                     │                 │
├──────────────────────────┼──────────────────────┼────────────────┤
│                          ▼                      ▼                 │
│              ┌──────────────────┐    ┌────────────────────────┐  │
│              │   SQLite DB      │    │  Ollama LLM            │  │
│              │   (selene.db)    │    │  (host machine)        │  │
│              │                  │    │  • mistral:7b          │  │
│              │ • raw_notes      │    │  • Local inference     │  │
│              │ • processed_notes│    │  • No internet needed  │  │
│              │ • sentiment_     │    └────────────────────────┘  │
│              │   history        │                                │
│              │ • detected_      │                                │
│              │   patterns       │                                │
│              │ • pattern_reports│                                │
│              │ • network_       │                                │
│              │   analysis_      │                                │
│              │   history        │                                │
│              └──────────────────┘                                │
│                          │                                        │
└──────────────────────────┼────────────────────────────────────────┘
                           │
┌──────────────────────────┼────────────────────────────────────────┐
│                    OUTPUT LAYER                                   │
├──────────────────────────┼────────────────────────────────────────┤
│                          ▼                                        │
│              ┌──────────────────────────────┐                    │
│              │   Obsidian Vault             │                    │
│              │   (./vault/Selene/)          │                    │
│              │                              │                    │
│              │   Selene/                    │                    │
│              │   ├── Sources/               │                    │
│              │   │   └── {note}.md          │                    │
│              │   ├── Concepts/              │                    │
│              │   │   └── {concept}.md       │                    │
│              │   ├── Themes/                │                    │
│              │   │   └── {theme}.md         │                    │
│              │   ├── Patterns/              │                    │
│              │   │   └── {pattern}.md       │                    │
│              │   └── {YYYY}/                │                    │
│              │       └── {note}.md          │                    │
│              └──────────────────────────────┘                    │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

---

## System Components

### 1. Input Layer

#### Webhook API
- **Endpoint**: `http://localhost:5678/webhook/api/drafts`
- **Method**: POST
- **Authentication**: None (local network only)
- **Expected Payload**:
```json
{
  "query": {
    "title": "Note Title",
    "content": "Note content...",
    "timestamp": "2025-10-30T10:00:00Z",
    "tags": ["optional", "tags"]
  }
}
```

#### Drafts App Integration
- iOS/Mac app for quick note capture
- Custom action sends notes to webhook
- Provides instant feedback on success/failure

### 2. Processing Layer (n8n Workflows)

#### Workflow 01: Ingestion
- **Purpose**: Entry point for all notes
- **Trigger**: Webhook (on-demand)
- **Processing**:
  1. Receive note via HTTP POST
  2. Calculate SHA-256 content hash
  3. Check for duplicates in database
  4. Store in `raw_notes` table with status='pending'
  5. Return success/duplicate response
- **Dependencies**: better-sqlite3
- **Output**: New row in `raw_notes` table

#### Workflow 02: LLM Processing
- **Purpose**: Extract concepts and themes using AI
- **Trigger**: Cron (every 30 seconds)
- **Processing**:
  1. Query for notes with status='pending'
  2. For each note:
     - Send content to Ollama
     - Parse LLM response for concepts and themes
     - Store results in `processed_notes` table
     - Update `raw_notes.status` to 'processed'
- **Dependencies**: better-sqlite3, Ollama API
- **Output**: New rows in `processed_notes` table
- **Ollama Prompt**: Extracts 3-5 key concepts and identifies primary/secondary themes

#### Workflow 03: Pattern Detection
- **Purpose**: Analyze trends in themes over time
- **Trigger**: Cron (daily at 6:00 AM)
- **Processing**:
  1. Query theme frequency over last 7, 30, 90 days
  2. Calculate trend direction (rising/falling/stable)
  3. Compute confidence scores based on data points
  4. Generate insights and recommendations
  5. Store in `detected_patterns` and `pattern_reports` tables
- **Dependencies**: n8n-nodes-sqlite
- **Output**: Pattern analysis stored in database

#### Workflow 04: Obsidian Export
- **Purpose**: Export processed notes as markdown files
- **Trigger**: Cron (daily at 7:00 AM)
- **Processing**:
  1. Query notes where `exported_to_obsidian=0` and `status='processed'`
  2. For each note:
     - Generate markdown with YAML frontmatter
     - Create concept and theme backlinks
     - Write file to vault directory
     - Update `raw_notes.exported_to_obsidian=1`
- **Dependencies**: n8n-nodes-sqlite, File System operations
- **Output**: Markdown files in Obsidian vault

#### Workflow 05: Sentiment Analysis
- **Purpose**: Analyze emotional tone and ADHD markers
- **Trigger**: Cron (every 45 seconds)
- **Processing**:
  1. Query processed notes where `sentiment_analyzed=0`
  2. Send to Ollama for sentiment analysis
  3. Extract emotional tone, energy level, stress indicators
  4. Detect ADHD-specific patterns
  5. Store in `sentiment_history` table
  6. Update `processed_notes.sentiment_analyzed=1`
- **Dependencies**: n8n-nodes-sqlite, Ollama API
- **Output**: Sentiment data in database

#### Workflow 06: Connection Network
- **Purpose**: Discover relationships between notes
- **Trigger**: Cron (every 6 hours)
- **Processing**:
  1. Query all processed notes
  2. Compare concepts and themes between note pairs
  3. Calculate connection strength (0.0-1.0)
  4. Store network statistics
  5. Generate connection graph data (future: for visualization)
- **Dependencies**: n8n-nodes-sqlite
- **Output**: Network analysis data in database

### 3. Data Layer

#### SQLite Database (selene.db)
- **Location**: `/selene/data/selene.db` (in container)
- **Host Path**: `./data/selene.db`
- **Size**: Grows with note volume (~1MB per 1000 notes)
- **Tables**: 8 main tables (see [Database Schema](database.md))

#### Ollama LLM Server
- **Location**: Host machine (not in container)
- **Access**: `http://host.docker.internal:11434` (from container)
- **Model**: mistral:7b (default, configurable)
- **Usage**:
  - Concept extraction (Workflow 02)
  - Sentiment analysis (Workflow 05)
- **Performance**: 10-30 seconds per note with Mistral 7B

### 4. Output Layer

#### Obsidian Vault
- **Location**: `./vault/Selene/` (configurable via env var)
- **Structure**:
  - `Sources/` - Original note content
  - `Concepts/` - Concept index files (one per concept)
  - `Themes/` - Theme index files (one per theme)
  - `Patterns/` - Pattern detection reports
  - `{YYYY}/` - Notes organized by year
- **Format**: Markdown with YAML frontmatter
- **Links**: Wikilinks (`[[concept]]`) for backlinks

---

## Data Flow

### Note Ingestion Flow

```
1. User captures note in Drafts app
   ↓
2. Drafts sends HTTP POST to webhook
   ↓
3. Workflow 01 receives note
   ↓
4. Calculate SHA-256 hash of content
   ↓
5. Check if hash exists in database
   ├─ YES → Return "duplicate" response, stop
   └─ NO  → Continue
   ↓
6. Insert into raw_notes table
   - status = 'pending'
   - exported_to_obsidian = 0
   ↓
7. Return success response to Drafts
```

### LLM Processing Flow

```
[Every 30 seconds]
   ↓
1. Workflow 02 triggers
   ↓
2. Query: SELECT * FROM raw_notes WHERE status='pending' LIMIT 1
   ├─ No results → Stop, wait for next trigger
   └─ Found note → Continue
   ↓
3. Send note content to Ollama API
   POST http://host.docker.internal:11434/api/generate
   {
     "model": "mistral:7b",
     "prompt": "Extract 3-5 key concepts and identify themes...",
     "stream": false
   }
   ↓
4. Ollama processes (10-30 seconds)
   ↓
5. Parse LLM response (JSON)
   - Extract concepts array
   - Extract primary_theme
   - Extract secondary_themes array
   - Extract confidence scores
   ↓
6. Insert into processed_notes table
   ↓
7. Update raw_notes.status = 'processed'
   ↓
8. Wait for next trigger
```

### Export Flow

```
[Daily at 7:00 AM]
   ↓
1. Workflow 04 triggers
   ↓
2. Query notes ready for export:
   SELECT * FROM raw_notes r
   JOIN processed_notes p ON r.id = p.raw_note_id
   WHERE r.exported_to_obsidian = 0
     AND r.status = 'processed'
   ↓
3. For each note:
   ↓
   a. Build markdown content:
      ---
      title: {{title}}
      created: {{created_at}}
      concepts: [{{concepts}}]
      theme: {{primary_theme}}
      ---

      {{content}}

      ## Concepts
      {{#each concepts}}
      - [[{{this}}]]
      {{/each}}

      ## Themes
      - [[{{primary_theme}}]]
   ↓
   b. Write to file:
      /obsidian/Selene/Sources/{{year}}/{{title}}.md
   ↓
   c. Update concept index files
   ↓
   d. Update theme index files
   ↓
   e. Update raw_notes.exported_to_obsidian = 1
   ↓
4. Complete
```

---

## Technology Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| **Orchestration** | n8n | Latest | Visual workflow automation |
| **Container** | Docker | 20.10+ | Isolated environment |
| **Runtime** | Node.js | 18+ | n8n execution environment |
| **Database** | SQLite | 3.x | Structured data storage |
| **DB Library** | better-sqlite3 | 11.0.0 | Native Node SQLite driver |
| **n8n Node** | n8n-nodes-sqlite | Latest | SQLite operations in workflows |
| **LLM** | Ollama | Latest | Local AI inference |
| **Model** | Mistral 7B | Latest | Concept extraction, sentiment |
| **Output** | Obsidian | Any | Knowledge vault |
| **Input** | Drafts | iOS/Mac | Note capture |

### Why These Technologies?

**n8n**
- Visual debugging (no log diving)
- Built-in scheduling (cron)
- HTTP/webhook support out of the box
- Active community and extensive documentation

**SQLite**
- Zero configuration
- File-based (easy backups)
- Fast for read-heavy workloads
- Excellent for personal data scale (< 1M notes)

**Ollama**
- Free and open source
- Runs locally (privacy)
- Easy model management
- Good performance on consumer hardware

**Docker**
- Consistent environment across systems
- Easy dependency management
- Simple updates and rollbacks
- Isolated from host system

---

## Deployment Architecture

### Container Setup

```
Host Machine
├── Docker Desktop
│   └── selene container
│       ├── n8n (port 5678)
│       ├── better-sqlite3 (globally installed)
│       ├── n8n-nodes-sqlite (community package)
│       └── Volumes:
│           ├── n8n_data → /home/node/.n8n (persistent n8n data)
│           ├── ./data → /selene/data (database)
│           ├── ./vault → /obsidian (export destination)
│           └── ./ → /workflows (workflow JSON files)
│
├── Ollama (port 11434)
│   └── Models: mistral:7b
│
└── Obsidian app
    └── Vault: ./vault/Selene
```

### Network Architecture

- **n8n Web UI**: Accessible at `http://localhost:5678` from host
- **Webhook**: Accessible at `http://localhost:5678/webhook/api/drafts` (local network)
- **Ollama**: Container accesses via `host.docker.internal:11434`
- **No external network**: All processing happens locally

### File System Layout

```
/Users/chaseeasterling/selene/
├── docker-compose.yml        # Container orchestration
├── Dockerfile                 # Custom n8n image
├── .env                       # Configuration (gitignored)
├── .env.example               # Configuration template
├── data/
│   └── selene.db             # SQLite database (gitignored)
├── vault/                     # Obsidian vault (gitignored)
│   └── Selene/
│       ├── Sources/
│       ├── Concepts/
│       ├── Themes/
│       ├── Patterns/
│       └── {YYYY}/
├── docs/                      # Documentation
├── database/
│   └── schema.sql            # Database schema
└── *.json                     # n8n workflow files (01-06)
```

---

## Security & Privacy

### Data Privacy

1. **No Cloud Services**: All processing happens on your machine
2. **No Telemetry**: n8n telemetry disabled via environment variables
3. **No Internet Required**: Except for initial setup (pulling images/models)
4. **Local LLM**: Ollama runs locally, no API calls to external services
5. **File-Based Storage**: SQLite database stored locally

### Access Control

1. **n8n Web UI**: Protected by HTTP Basic Auth
   - Username: `admin` (configurable)
   - Password: Set in `.env` file
2. **Webhook Endpoint**: No authentication (assumes local network trust)
   - Only accessible on `localhost` by default
   - For remote access, consider adding webhook authentication
3. **Database**: File permissions restrict access to user account

### Recommendations

1. **Change Default Password**: Update `N8N_BASIC_AUTH_PASSWORD` in `.env`
2. **Backup Encryption**: Encrypt database backups if stored on cloud
3. **Network Isolation**: Keep n8n on local network, don't expose to internet
4. **Regular Updates**: Keep Docker images and Ollama updated

---

## Performance Characteristics

### Processing Times

| Operation | Duration | Frequency |
|-----------|----------|-----------|
| **Note Ingestion** | < 1 second | On-demand |
| **LLM Processing** | 10-30 seconds | Every 30s (1 note at a time) |
| **Sentiment Analysis** | 8-20 seconds | Every 45s |
| **Pattern Detection** | 5-15 seconds | Daily @ 6am |
| **Obsidian Export** | ~1 second per note | Daily @ 7am |
| **Connection Network** | 10-60 seconds | Every 6 hours |

### Resource Usage

| Resource | Typical Usage | Peak Usage |
|----------|---------------|------------|
| **CPU** | 5-10% idle | 80-100% during LLM processing |
| **RAM** | 2-4 GB | 6-8 GB with large notes |
| **Disk** | 1 MB per 1000 notes | Grows linearly |
| **Network** | None (after setup) | Local loopback only |

### Scalability Limits

| Metric | Limit | Notes |
|--------|-------|-------|
| **Total Notes** | ~100,000 | SQLite performs well up to this scale |
| **Note Size** | 10,000 characters | Larger notes slow LLM processing |
| **Concurrent Processing** | 1 note | Sequential to avoid resource exhaustion |
| **Daily Ingestion** | ~2,880 notes | 1 note per 30s = 2 per minute |

### Optimization Opportunities

1. **Parallel LLM Processing**: Process multiple notes simultaneously (requires more RAM)
2. **Database Indexing**: Already optimized with indexes on common queries
3. **Caching**: Cache LLM responses for identical content (future enhancement)
4. **Batch Export**: Export notes in batches rather than one at a time

---

## Design Principles

### 1. Visual-First Development

**Problem**: Traditional code-based automation requires debugging through logs and code inspection.

**Solution**: n8n provides a visual canvas where you can:
- See the entire pipeline at a glance
- Debug by inspecting node outputs
- Modify logic without code changes
- Test workflows with sample data

### 2. Privacy by Design

**Problem**: Many knowledge management systems require cloud services and expose your data.

**Solution**: Selene runs entirely on your machine:
- Ollama processes locally (no API calls)
- SQLite stores data in a local file
- n8n runs in a local container
- No telemetry or phone-home

### 3. ADHD-Friendly Automation

**Problem**: Manual note organization requires sustained focus and creates friction.

**Solution**: Automatic processing removes cognitive load:
- No manual tagging required
- Concepts extracted automatically
- Patterns detected without effort
- Notes organized while you sleep

### 4. Modular Architecture

**Problem**: Monolithic systems are hard to maintain and customize.

**Solution**: Six independent workflows:
- Each workflow has a single responsibility
- Workflows can be enabled/disabled independently
- Easy to add new workflows
- Simple to modify existing logic

### 5. Fail-Safe Processing

**Problem**: Errors in one note can block processing of subsequent notes.

**Solution**: Sequential, transaction-based processing:
- One note at a time (no concurrent failures)
- Database transactions ensure consistency
- Failed notes remain in pending state
- Automatic retry on next trigger

### 6. Data Provenance

**Problem**: Losing track of where data came from and how it was processed.

**Solution**: Complete audit trail:
- `raw_notes.source_type` tracks input source
- `raw_notes.imported_at` vs `processed_at` shows latency
- `processed_notes` links back to original via `raw_note_id`
- Status field tracks lifecycle: pending → processed → archived

---

## Integration Points

### Input Integrations

**Current**:
- Drafts app (iOS/Mac) via webhook

**Future Possibilities**:
- Obsidian Quick Capture (via plugin)
- Apple Notes (via Shortcuts)
- Bear app (via x-callback-url)
- Email (via IMAP polling)
- Voice notes (via Whisper transcription)

### Output Integrations

**Current**:
- Obsidian vault (markdown export)

**Future Possibilities**:
- Notion (via API)
- Roam Research (via API)
- LogSeq (file-based like Obsidian)
- JSON API (for custom consumers)
- Graph databases (Neo4j for network visualization)

### LLM Integrations

**Current**:
- Ollama (local inference)

**Future Possibilities**:
- OpenAI API (cloud-based)
- Anthropic Claude API (cloud-based)
- Local models (llama.cpp, GPT4All)
- Fine-tuned models (for personalized extraction)

---

## Next Steps

- **[Database Schema](database.md)** - Detailed table structures and relationships
- **[Design Decisions](decisions.md)** - Why we made specific architectural choices
- **[Workflow Overview](../workflows/overview.md)** - Deep dive into each workflow
- **[Troubleshooting](../troubleshooting/common-issues.md)** - Common problems and solutions

---

**Last Updated**: October 30, 2025
**Author**: Chase Easterling
**Version**: 1.0.0
