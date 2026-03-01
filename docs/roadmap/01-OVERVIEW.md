# Selene n8n - Overview

**Created:** 2025-10-18
**Purpose:** Rebuild Selene as a visual, maintainable n8n workflow system

## Executive Summary

This project translates the Selene Python codebase into a clean, visual n8n-based system. You've built a comprehensive note processing system but haven't been able to use it due to complexity. This fresh start uses n8n's visual workflows to make the system:

- **Simple to understand** - See the entire flow on one screen
- **Easy to debug** - Visual execution logs and error handling
- **Maintainable yourself** - No Python expertise required
- **Incrementally buildable** - Start with basics, add features as needed

## What We Learned from the Python Codebase

### Core Architecture (What We're Keeping)

#### 1. Database Schema ✅ REUSE AS-IS

- SQLite database with excellent schema design
- Tables: `raw_notes`, `processed_notes`, `themes`, `concepts`, `connections`, `patterns`
- Path: `/selene/data/schema.sql` (304 lines, production-ready)
- **Action:** Copy schema.sql to new project and reuse

See [10-DATABASE-SCHEMA.md](./10-DATABASE-SCHEMA.md) for full details.

#### 2. Drafts Integration Pattern ✅ SIMPLIFY FOR N8N

- Current: Complex Python client with x-callback-url, HTTP server, retries
- n8n approach: Simple webhook endpoint + HTTP request nodes
- Key insight: Drafts can POST directly to n8n webhooks

See [12-DRAFTS-INTEGRATION.md](./12-DRAFTS-INTEGRATION.md) for implementation.

#### 3. Ollama/LLM Processing ✅ SIMPLIFY FOR N8N

- Current: Sophisticated adapter with retry logic, prompt templates
- n8n approach: HTTP Request node to `localhost:11434/api/generate`
- Key prompts preserved:
  - Concept extraction: "Extract 5-10 key concepts as JSON array"
  - Theme detection: "Identify primary and secondary themes as JSON"
  - Entity extraction: "Extract people, places, organizations, dates as JSON"

See [11-OLLAMA-INTEGRATION.md](./11-OLLAMA-INTEGRATION.md) for prompts and configuration.

#### 4. Obsidian Export ✅ SIMPLIFY FOR N8N

- Current: Complex Python exporter with 1000+ lines
- n8n approach: Simple workflow that queries DB and writes markdown files
- Vault structure preserved: `Selene/Concepts/`, `Selene/Themes/`, `Selene/Patterns/`

See [04-PHASE-2-OBSIDIAN.md](./04-PHASE-2-OBSIDIAN.md) for implementation.

### What We're NOT Keeping

- ❌ **Python complexity** - All Python code stays archived
- ❌ **Virtual environments** - No more venv/pyenv
- ❌ **MCP server** - n8n replaces this orchestration layer
- ❌ **Production packaging** - Start simple, build up
- ❌ **268 tests** - Start fresh with simpler validation
- ❌ **Privacy guard scanning** - Manual localhost validation is enough

## n8n Workflow Architecture

### High-Level Flow

```
┌─────────────────┐
│  Drafts Action  │  User creates note
└────────┬────────┘
         │ HTTP POST
         ▼
┌─────────────────┐
│  01: Ingestion  │  Store in raw_notes
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 02: LLM Process │  Extract concepts/themes
└────────┬────────┘
         │
         ├──────────────┬─────────────┐
         ▼              ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ 05: Sentiment│ │ 06: Connect  │ │ Other analysis│
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └────────────────┼────────────────┘
                        ▼
              ┌─────────────────┐
              │ 04: Export      │  To Obsidian
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ 03: Patterns    │  Detect trends
              └─────────────────┘
```

### Workflow Files

Located in `/workflows/` directory:

1. **01-ingestion/** - Webhook receiver, stores raw notes
2. **02-llm-processing/** - Extracts concepts and themes via Ollama
3. **03-pattern-detection/** - Analyzes trends (future)
4. **04-obsidian-export/** - Exports to markdown (future)
5. **05-sentiment-analysis/** - Sentiment and emotional tone
6. **06-connection-network/** - Links between notes

See [13-N8N-WORKFLOW-SPECS.md](./13-N8N-WORKFLOW-SPECS.md) for detailed node configurations.

## Project Structure

```
/Users/chaseeasterling/selene/
│
├── README.md                    # Project overview and quick start
├── ROADMAP.md                   # Links to this documentation
│
├── docs/
│   └── roadmap/                # Modular documentation (you are here)
│       ├── 00-INDEX.md         # Documentation index
│       ├── 01-OVERVIEW.md      # This file
│       ├── 02-CURRENT-STATUS.md
│       └── ...
│
├── database/
│   ├── schema.sql              # SQLite schema
│   └── selene.db               # Database file
│
├── workflows/
│   ├── 01-ingestion/
│   │   ├── workflow.json
│   │   └── README.md
│   ├── 02-llm-processing/
│   │   ├── workflow.json
│   │   └── README.md
│   └── ...
│
├── drafts-actions/
│   ├── send-to-selene.js       # Main Drafts action
│   └── test-connection.js      # Test n8n connection
│
├── config/
│   ├── n8n.env                 # n8n environment variables
│   └── ollama-models.txt       # Required Ollama models
│
├── scripts/
│   ├── setup.sh                # Initial setup script
│   ├── backup-db.sh            # Database backup
│   └── test-ollama.sh          # Test Ollama connection
│
└── vault/                      # Obsidian vault (export target)
    └── Selene/
        ├── Concepts/
        ├── Themes/
        ├── Patterns/
        └── Sources/
```

## Key Differences from Python Version

| Aspect | Python Version | n8n Version |
|--------|---------------|-------------|
| **Codebase Size** | 10,000+ lines | ~6 workflows (~800 lines equivalent) |
| **Setup Complexity** | venv, dependencies, config files | Import JSON, connect nodes |
| **Debugging** | Stack traces, logging | Visual execution logs |
| **Maintenance** | Python expertise required | Drag & drop nodes |
| **Testing** | 268 unit tests | Manual workflow testing |
| **Extensibility** | Write Python code | Add n8n nodes |
| **Visibility** | Code in files | Visual canvas |

## Success Criteria

### Week 1 ✅ COMPLETE
- ✅ 1 note successfully processed end-to-end
- ✅ Can query the note in SQLite
- ✅ Drafts action works reliably

### Week 2
- ✅ 10+ notes in system
- ⬜ Notes exported to Obsidian
- ⬜ Concept links work in Obsidian

### Week 3-4
- ⬜ 50+ notes processed
- ⬜ Pattern detection running daily
- ⬜ Can see theme trends

### Month 1
- ⬜ Using system daily for new notes
- ⬜ Comfortable modifying workflows
- ⬜ Backups running automatically

## Design Principles

1. **Start minimal** - Phase 1 first, add features only when needed
2. **Visual over code** - n8n canvas beats Python files
3. **Simple over perfect** - Working beats comprehensive
4. **Incremental** - Each phase builds on previous
5. **ADHD-friendly** - Low friction, high visibility

## Next Steps

1. Check [02-CURRENT-STATUS.md](./02-CURRENT-STATUS.md) to see what's complete
2. Pick the next incomplete phase
3. Read that phase's documentation
4. Implement and test
5. Update status file

## Support Resources

- **Ollama API**: https://github.com/ollama/ollama/blob/main/docs/api.md
- **n8n Docs**: https://docs.n8n.io/
- **SQLite Docs**: https://www.sqlite.org/docs.html
- **Project README**: /selene/README.md
