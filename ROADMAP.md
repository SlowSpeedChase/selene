# Selene n8n Migration Roadmap

**Created:** 2025-10-18
**Last Updated:** 2026-01-10
**Status:** Phase 1-3 Complete ✅ | Phase 7.1 Complete ✅ | Phase 7.2 Complete ✅ | Thread System Phase 1-2 Complete ✅

---

## 📚 Documentation Structure

This roadmap has been reorganized into focused, modular documents to make it easier for AI agents and developers to work with specific aspects of the system.

### 🚀 **Start Here**

**New to the project?** Read these in order:

1. **[Documentation Index](./docs/roadmap/00-INDEX.md)** - How to navigate this documentation
2. **[Overview](./docs/roadmap/01-OVERVIEW.md)** - System architecture and goals
3. **[Current Status](./docs/roadmap/02-CURRENT-STATUS.md)** - What's done, what's next

### 📋 **Implementation Phases**

Work on specific features:

- **[Phase 1: Core System](./docs/roadmap/03-PHASE-1-CORE.md)** ✅ COMPLETE - Drafts → Ollama → SQLite
- **[Phase 1.5: UUID Tracking Foundation](./docs/roadmap/09-UUID-TRACKING-FOUNDATION.md)** ✅ COMPLETE - Draft UUID tracking & edit detection
- **[Phase 2: Obsidian Export](./docs/roadmap/04-PHASE-2-OBSIDIAN.md)** ✅ COMPLETE - ADHD-optimized export with visual indicators
- **[Phase 3: Pattern Detection](./docs/roadmap/05-PHASE-3-PATTERNS.md)** 🔄 Ready for testing
- **[Phase 4: Polish & Enhancements](./docs/roadmap/06-PHASE-4-POLISH.md)** ⬜ Future
- **[Phase 6: Event-Driven Architecture](./docs/roadmap/08-PHASE-6-EVENT-DRIVEN.md)** ⚡ PARTIAL - Workflows 01-05 complete
- **[Phase 7: Things Integration](./docs/roadmap/16-PHASE-7-THINGS.md)** 📋 PLANNING COMPLETE - Task extraction via MCP (ready to implement)

### 🔧 **Technical Reference**

Integration details and specifications:

- **[Database Schema](./docs/roadmap/10-DATABASE-SCHEMA.md)** - SQLite tables and queries
- **[Ollama Integration](./docs/roadmap/11-OLLAMA-INTEGRATION.md)** - LLM prompts and configuration
- **[Drafts Integration](./docs/roadmap/12-DRAFTS-INTEGRATION.md)** - Drafts app connection
- **[n8n Workflow Specs](./docs/roadmap/13-N8N-WORKFLOW-SPECS.md)** - Detailed node configurations
- **[Configuration Files](./docs/roadmap/14-CONFIGURATION.md)** - Environment and config
- **[Testing Procedures](./docs/roadmap/15-TESTING.md)** - How to test and validate

### 🏗️ **Foundation Improvements**

Infrastructure and architectural enhancements:

- **[UUID Tracking Foundation](./docs/roadmap/09-UUID-TRACKING-FOUNDATION.md)** - Draft identification and edit detection
- **[n8n 2.x Upgrade](./docs/plans/2026-01-01-n8n-upgrade-design.md)** 📋 DESIGN COMPLETE - Upgrade from 1.110.1 to 2.1.4
  - Security hardening (task runners, isolated Code execution)
  - SQLite pooling (up to 10x faster queries)
  - MCP nodes for SeleneChat integration
  - Publish/Save workflow pattern

### 🎯 **Phase 7: Things Integration (Design Revised 2025-12-30)**

Task extraction with classification - route actionable items to Things:

- **[📋 Phase 7 Roadmap](./docs/roadmap/16-PHASE-7-THINGS.md)** - START HERE: Complete phase documentation
- **[🎯 Phase 7.1 Design](./docs/plans/2025-12-30-task-extraction-planning-design.md)** - Task Extraction with Classification design
- **[🗓️ Phase 7.2 Design](./docs/plans/2025-12-31-phase-7.2-selenechat-planning-design.md)** - SeleneChat Planning Integration design
- **[🔀 Phase 7.2d Design](./docs/plans/2025-12-31-ai-provider-toggle-design.md)** - AI Provider Toggle (Local/Cloud)
- **[📊 Metadata Definitions](./docs/architecture/metadata-definitions.md)** - Field specifications for classification
- **[🏛️ Architecture](./docs/architecture/things-integration.md)** - Technical design and system architecture
- **[👤 User Stories](./docs/user-stories/things-integration-stories.md)** - User scenarios and acceptance criteria
- **[🧠 ADHD Features Deep Dive](./docs/planning/adhd-features-integration.md)** - For planning future phases (8+)

**Phase 7.2 Sub-phases:**
- Phase 7.2a: Foundation ✅ COMPLETE
- Phase 7.2b: Planning Tab ✅ COMPLETE
- Phase 7.2c: Planning Conversations ✅ COMPLETE
- Phase 7.2d: AI Provider Toggle ✅ COMPLETE
- Phase 7.2e: Bidirectional Things Flow ✅ COMPLETE
- Phase 7.2f: Things Project Grouping ✅ COMPLETE
  - **[📋 Design Document](./docs/plans/2026-01-01-project-grouping-design.md)**
  - 7.2f.1: Basic Project Creation ✅ COMPLETE
  - 7.2f.2: Auto-Assignment for New Tasks ✅ COMPLETE
  - 7.2f.3: Headings Within Projects ✅ COMPLETE
  - 7.2f.4: Oversized Task Detection ✅ COMPLETE
  - 7.2f.5: Project Completion ✅ COMPLETE
  - 7.2f.6: Sub-Project Suggestions ✅ COMPLETE

**Key Changes:**
- Phase 7.1: Task Extraction with Classification ✅ COMPLETE (2025-12-30)
- Phase 7.2: SeleneChat Planning Integration ✅ COMPLETE (2026-01-10)
- Phase 7.3: Cloud AI Integration (with sanitization layer)
- Phase 7.4: Contextual Surfacing (thread continuation)

### 🧵 **Thread System (Parallel Track)**

Semantic note clustering and thread detection - implemented via user stories:

- **[📋 Design Docs Index](./docs/plans/INDEX.md)** - Design document tracking and status
- **[🎯 Thread System Design](./docs/plans/2026-01-04-selene-thread-system-design.md)** - Architecture and design

**Thread System Phases:**
- thread-system-1: Foundation (Embeddings + Associations) ✅ COMPLETE
  - US-040: Database Migration
  - US-041: Embedding Generation Workflow
  - US-042: Batch Embed Existing Notes
  - US-043: Association Computation Workflow
  - US-044: Verify Note Clusters
- thread-system-2: Thread Detection ✅ COMPLETE
  - US-045: Thread Detection Workflow
  - US-046: Thread Detection Testing & Tuning
- thread-system-3: Living System (Future)
  - Wire Embedding into Processing Pipeline
  - Thread Reconsolidation Workflow
  - Thread Splitting/Merging
- thread-system-4: Interfaces (Future)
  - Thread Export to Obsidian
  - SeleneChat Thread Queries
  - Link Tasks to Threads

### 🛠️ **Setup & Maintenance**

Getting started and troubleshooting:

- **[Setup Instructions](./docs/roadmap/20-SETUP-INSTRUCTIONS.md)** - Initial setup from scratch
- **[Migration Guide](./docs/roadmap/21-MIGRATION-GUIDE.md)** - Migrating from Python version
- **[Troubleshooting](./docs/roadmap/22-TROUBLESHOOTING.md)** - Common issues and solutions

---

## Quick Start

### For First-Time Setup

```bash
# 1. Navigate to project
cd /Users/chaseeasterling/selene

# 2. Read the overview
cat docs/roadmap/01-OVERVIEW.md

# 3. Follow setup instructions
cat docs/roadmap/20-SETUP-INSTRUCTIONS.md

# 4. Check current status
cat docs/roadmap/02-CURRENT-STATUS.md
```

### For Continuing Work

```bash
# 1. Check what's done
cat docs/roadmap/02-CURRENT-STATUS.md

# 2. Pick next phase
cat docs/roadmap/04-PHASE-2-OBSIDIAN.md  # or whichever phase is next

# 3. Reference technical docs as needed
cat docs/roadmap/10-DATABASE-SCHEMA.md
cat docs/roadmap/11-OLLAMA-INTEGRATION.md
```

### For AI Agents

**Agent working on Phase 2 (Obsidian Export):**
```
Read: 01-OVERVIEW.md + 04-PHASE-2-OBSIDIAN.md + 10-DATABASE-SCHEMA.md
Context: Only Obsidian export, database queries, and system overview
```

**Agent working on LLM improvements:**
```
Read: 11-OLLAMA-INTEGRATION.md + 03-PHASE-1-CORE.md
Context: Only Ollama prompts and workflow 02
```

**Agent updating status:**
```
Read: 02-CURRENT-STATUS.md + specific phase file
Task: Mark tasks complete, update metrics
```

---

## Current Status Summary

**✅ Phase 1 Complete** (October 30, 2025)
- 10 notes successfully processed
- Drafts integration working
- LLM processing (concepts, themes, sentiment) working
- Database storage working
- Average confidence score: 0.82

**⚡ Phase 6 Partially Complete** (October 31, 2025)
- Workflows 01 & 02 migrated to event-driven architecture
- Processing time reduced from 20-25s to ~14s (3x faster)
- 100% resource efficiency (no wasted cron executions)
- Workflows 04 & 05 still using cron/schedule triggers

**🔨 Phase 1.5 In Progress** (UUID Tracking Foundation - Started 2025-11-01)
- Add source_uuid field to database
- Track individual drafts by UUID
- Implement edit detection (UUID-first duplicate logic)
- Foundation for version tracking and edit history

**⬜ SeleneChat Enhancements** (Planning)
- Chat session summaries to database
- Query pattern tracking for ADHD memory support
- Integration with Selene database for conversation history

**⬜ SeleneChat Visual Redesign: Forest Study** (Ready - [Design](./docs/plans/2026-01-05-selenechat-redesign-design.md) | [Implementation Plan](./docs/plans/2026-01-05-selenechat-redesign-implementation.md))
- Earthy color palette (cream, sage, terracotta, muted blue)
- Serif typography for reading (Charter), sans for UI (SF Pro)
- Surface color shifts for depth (no shadows)
- Split-view list/detail layout
- ADHD-optimized: calm + sharp aesthetic
- 13-task implementation plan ready

**⬜ SeleneChat Interface Improvements** (Future - [Design Research](./docs/plans/2026-01-05-selenechat-interface-inspiration-design.md))
- Command palette (`⌘K`) for universal search/actions
- Citation hover preview (Perplexity-style)
- Planning tab simplification (progressive disclosure)
- Daily planning view with resurfaced threads
- Concept graph visualization
- Focus mode (single-project view)

**⬜ Phase 2 Next** (Obsidian Export - After Phase 1.5)
- Export processed notes to markdown
- Create Obsidian vault structure
- Test concept/theme linking

See [02-CURRENT-STATUS.md](./docs/roadmap/02-CURRENT-STATUS.md) for details.

---

## Project Goals

Transform the complex Python Selene codebase into a simple, visual n8n workflow system that:

- ✅ **Is simple to understand** - Visual workflows on one screen
- ✅ **Is easy to debug** - Execution logs and clear flow
- ✅ **Is maintainable** - No Python expertise needed
- ⬜ **Works daily** - Reliable note processing
- ⬜ **Grows incrementally** - Add features as needed

---

## Architecture Overview

```
┌─────────────────┐
│  Drafts App     │  User creates note
└────────┬────────┘
         │ HTTP POST
         ▼
┌─────────────────┐
│  n8n Workflows  │  Process and analyze
│  (6 workflows)  │
└────────┬────────┘
         │
         ├──────────────┬─────────────┐
         ▼              ▼             ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   SQLite DB  │ │   Ollama LLM │ │   Obsidian   │
└──────────────┘ └──────────────┘ └──────────────┘
```

**Components:**
- **Drafts** - Note capture
- **n8n** - Workflow orchestration
- **Ollama** - Local LLM (mistral:7b)
- **SQLite** - Data storage
- **Obsidian** - Knowledge base export

See [01-OVERVIEW.md](./docs/roadmap/01-OVERVIEW.md) for detailed architecture.

---

## Key Improvements Over Python Version

| Aspect | Python | n8n |
|--------|--------|-----|
| **Codebase Size** | 10,000+ lines | ~800 lines equivalent |
| **Setup** | venv, dependencies, complex config | Import JSON workflows |
| **Debugging** | Stack traces, logs | Visual execution logs |
| **Maintenance** | Python expertise | Drag & drop nodes |
| **Visibility** | Code in files | Visual canvas |

---

## How to Use This Documentation

### I'm a developer starting Phase 2

1. Read [04-PHASE-2-OBSIDIAN.md](./docs/roadmap/04-PHASE-2-OBSIDIAN.md)
2. Reference [10-DATABASE-SCHEMA.md](./docs/roadmap/10-DATABASE-SCHEMA.md) for queries
3. Reference [13-N8N-WORKFLOW-SPECS.md](./docs/roadmap/13-N8N-WORKFLOW-SPECS.md) for node configs
4. Update [02-CURRENT-STATUS.md](./docs/roadmap/02-CURRENT-STATUS.md) when done

### I'm an AI agent working on LLM improvements

1. Read [11-OLLAMA-INTEGRATION.md](./docs/roadmap/11-OLLAMA-INTEGRATION.md)
2. Read [03-PHASE-1-CORE.md](./docs/roadmap/03-PHASE-1-CORE.md) (workflow 02 section)
3. Make changes to prompts or parsing
4. Update documentation with findings

### I'm troubleshooting an issue

1. Check [22-TROUBLESHOOTING.md](./docs/roadmap/22-TROUBLESHOOTING.md)
2. Review [15-TESTING.md](./docs/roadmap/15-TESTING.md) for validation steps
3. Check relevant technical doc (10-15) for specifics

### I need to set up from scratch

1. Read [01-OVERVIEW.md](./docs/roadmap/01-OVERVIEW.md)
2. Follow [20-SETUP-INSTRUCTIONS.md](./docs/roadmap/20-SETUP-INSTRUCTIONS.md)
3. Run tests from [15-TESTING.md](./docs/roadmap/15-TESTING.md)

---

## Documentation Maintenance

**When to update documentation:**

- ✅ After completing any phase → Update [02-CURRENT-STATUS.md](./docs/roadmap/02-CURRENT-STATUS.md)
- ✅ When modifying workflows → Update [13-N8N-WORKFLOW-SPECS.md](./docs/roadmap/13-N8N-WORKFLOW-SPECS.md)
- ✅ When changing prompts → Update [11-OLLAMA-INTEGRATION.md](./docs/roadmap/11-OLLAMA-INTEGRATION.md)
- ✅ When solving issues → Add to [22-TROUBLESHOOTING.md](./docs/roadmap/22-TROUBLESHOOTING.md)
- ✅ Weekly during active development → Review and update all relevant docs

**Keep documentation:**
- Focused (each file covers one topic)
- Current (update as you work)
- Actionable (clear next steps)
- Searchable (good headings and structure)

---

## Questions?

- **Documentation index:** [00-INDEX.md](./docs/roadmap/00-INDEX.md)
- **Current status:** [02-CURRENT-STATUS.md](./docs/roadmap/02-CURRENT-STATUS.md)
- **Project overview:** [01-OVERVIEW.md](./docs/roadmap/01-OVERVIEW.md)

---

## Version History

- **2026-01-10**: Synced ROADMAP with stories INDEX - Phase 7.2 fully complete, Thread System phases 1-2 complete
  - Phase 7.2f.2-6 all implemented and merged to main
  - TypeScript backend replaced n8n (Fastify + launchd)
  - Thread detection workflow complete with 2 detected threads
- **2026-01-05**: Added SeleneChat Forest Study Redesign to roadmap (design + 13-task implementation plan ready)
- **2026-01-05**: Added SeleneChat Interface Improvements to roadmap (design research from Perplexity, Things, Sunsama, Raycast, Linear)
- **2026-01-04**: Synced documentation - Phase 7.2e (Bidirectional Things) and 7.2f.1 (Basic Project Creation) marked complete
- **2026-01-01**: n8n 2.x Upgrade design complete - Upgrade from 1.110.1 to 2.1.4
  - Security hardening, SQLite performance, MCP integration
  - See [design document](./docs/plans/2026-01-01-n8n-upgrade-design.md)
- **2026-01-01**: Phase 7.2f design complete - Things Project Grouping with script-driven architecture
  - Auto-create projects from concept clusters (3+ tasks)
  - Auto-assign new tasks to existing projects
  - Hierarchical breakdown detection
  - See [design document](./docs/plans/2026-01-01-project-grouping-design.md)
- **2025-12-31**: Phase 7.2d complete - AI Provider Toggle (Local/Cloud switching in Planning tab)
- **2025-12-31**: Phase 7.2f added to roadmap - Things Project Grouping (auto-create projects for related tasks)
- **2025-12-31**: Phase 7.2 design complete - SeleneChat Planning Integration with dual AI routing
- **2025-12-31**: Workflow 08-Daily-Summary completed - Automated daily executive summaries with Ollama
- **2025-12-30**: Phase 7.1 design revised - Task Extraction with Classification, new architectural layers
- **2025-11-13**: Added SeleneChat Enhancements phase - Chat session summaries to database
- **2025-11-01**: Added Phase 1.5 (UUID Tracking Foundation) - Draft identification and edit detection
- **2025-10-31**: Reorganized into modular documentation structure
- **2025-10-30**: Phase 1 completed (10 notes processed, all features working)
- **2025-10-18**: Initial roadmap created, project started

---

**The old monolithic roadmap has been replaced with this modular structure. All content has been preserved and reorganized into focused, easy-to-use documents.**

**Start with [00-INDEX.md](./docs/roadmap/00-INDEX.md) to navigate the documentation.**
