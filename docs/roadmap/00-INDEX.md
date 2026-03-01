# Selene n8n Roadmap - Index

**Created:** 2025-10-18
**Last Updated:** 2025-11-24
**Purpose:** Master index for modular roadmap documentation

## Overview

This directory contains the complete Selene n8n migration roadmap, broken into focused modules that can be used independently by AI agents or developers working on specific aspects of the system.

## Quick Start

For implementation work, read in this order:
1. [01-OVERVIEW.md](./01-OVERVIEW.md) - System architecture and goals
2. [02-CURRENT-STATUS.md](./02-CURRENT-STATUS.md) - What's been completed
3. [03-PHASE-*.md](./03-PHASE-1-CORE.md) - Implementation phase you're working on

## Document Structure

### Core Documentation
- **[01-OVERVIEW.md](./01-OVERVIEW.md)** - Executive summary, architecture, what we learned from Python codebase
- **[02-CURRENT-STATUS.md](./02-CURRENT-STATUS.md)** - Completed phases, current state, success metrics

### Implementation Phases
- **[03-PHASE-1-CORE.md](./03-PHASE-1-CORE.md)** - Minimal viable system (Drafts → Ollama → SQLite)
- **[04-PHASE-2-OBSIDIAN.md](./04-PHASE-2-OBSIDIAN.md)** - Export processed notes to Obsidian vault
- **[05-PHASE-3-PATTERNS.md](./05-PHASE-3-PATTERNS.md)** - Pattern detection and theme trends
- **[06-PHASE-4-POLISH.md](./06-PHASE-4-POLISH.md)** - Error handling and enhancements
- **[16-PHASE-7-THINGS.md](./16-PHASE-7-THINGS.md)** - Things 3 integration via MCP (task extraction, projects, ADHD features)
- **[08-PHASE-6-EVENT-DRIVEN.md](./08-PHASE-6-EVENT-DRIVEN.md)** - Event-driven workflow architecture

### Technical Reference
- **[10-DATABASE-SCHEMA.md](./10-DATABASE-SCHEMA.md)** - SQLite database structure
- **[11-OLLAMA-INTEGRATION.md](./11-OLLAMA-INTEGRATION.md)** - LLM integration patterns and prompts
- **[12-DRAFTS-INTEGRATION.md](./12-DRAFTS-INTEGRATION.md)** - Drafts app connection
- **[13-N8N-WORKFLOW-SPECS.md](./13-N8N-WORKFLOW-SPECS.md)** - Detailed workflow node configurations
- **[14-CONFIGURATION.md](./14-CONFIGURATION.md)** - Environment and config files
- **[15-TESTING.md](./15-TESTING.md)** - Testing procedures and validation

### Maintenance
- **[20-SETUP-INSTRUCTIONS.md](./20-SETUP-INSTRUCTIONS.md)** - Initial setup from scratch
- **[21-MIGRATION-GUIDE.md](./21-MIGRATION-GUIDE.md)** - Migrating from Python version
- **[22-TROUBLESHOOTING.md](./22-TROUBLESHOOTING.md)** - Common issues and solutions

### Phase 7 Supporting Documents
- **[../THINGS-INTEGRATION-SUMMARY.md](../THINGS-INTEGRATION-SUMMARY.md)** - Complete integration overview and next steps
- **[../architecture/things-integration.md](../architecture/things-integration.md)** - Technical architecture and design
- **[../user-stories/things-integration-stories.md](../user-stories/things-integration-stories.md)** - User scenarios and acceptance criteria
- **[../planning/adhd-features-integration.md](../planning/adhd-features-integration.md)** - Deep dive into ADHD features (for future sessions)
- **[../plans/auto-create-tasks-from-notes.md](../plans/auto-create-tasks-from-notes.md)** - Phase 7.1 implementation spec

## How to Use This Documentation

### For AI Agents

**Agent Type: Implementation**
- Read: 01-OVERVIEW.md + specific phase file (03-PHASE-*.md) + 13-N8N-WORKFLOW-SPECS.md
- Context: Only the phase being worked on, workflow specs, and overview

**Agent Type: Database Work**
- Read: 10-DATABASE-SCHEMA.md + 01-OVERVIEW.md (database section only)
- Context: Database structure and queries only

**Agent Type: Integration (Drafts/Ollama)**
- Read: 11-OLLAMA-INTEGRATION.md or 12-DRAFTS-INTEGRATION.md + 01-OVERVIEW.md
- Context: Specific integration details only

**Agent Type: Testing/Validation**
- Read: 15-TESTING.md + 02-CURRENT-STATUS.md
- Context: Test procedures and current state

**Agent Type: Maintenance/Updates**
- Read: 02-CURRENT-STATUS.md + specific phase files
- Task: Update status, mark tasks complete, add notes

### For Human Developers

**First time setup:**
1. Read 01-OVERVIEW.md
2. Follow 20-SETUP-INSTRUCTIONS.md
3. Check 02-CURRENT-STATUS.md to see what's done

**Working on a feature:**
1. Check which phase it's in (02-CURRENT-STATUS.md)
2. Read that phase's file (03-PHASE-*.md)
3. Reference technical docs as needed (10-15)

**Debugging:**
1. Check 22-TROUBLESHOOTING.md
2. Review 15-TESTING.md for validation steps
3. Check workflow specs in 13-N8N-WORKFLOW-SPECS.md

## Project Structure

```
/selene/
├── ROADMAP.md                    # Main entry point (links to this index)
├── docs/
│   ├── THINGS-INTEGRATION-SUMMARY.md   # Phase 7 overview and next steps
│   ├── architecture/
│   │   └── things-integration.md       # Phase 7 technical architecture
│   ├── user-stories/
│   │   └── things-integration-stories.md  # Phase 7 user scenarios
│   ├── planning/
│   │   └── adhd-features-integration.md   # ADHD features deep dive
│   ├── plans/
│   │   └── auto-create-tasks-from-notes.md  # Phase 7.1 implementation spec
│   └── roadmap/                  # This directory
│       ├── 00-INDEX.md          # This file
│       ├── 01-OVERVIEW.md
│       ├── 02-CURRENT-STATUS.md
│       ├── 03-PHASE-1-CORE.md
│       ├── 04-PHASE-2-OBSIDIAN.md
│       ├── 05-PHASE-3-PATTERNS.md
│       ├── 06-PHASE-4-POLISH.md
│       ├── 08-PHASE-6-EVENT-DRIVEN.md
│       ├── 10-DATABASE-SCHEMA.md
│       ├── 11-OLLAMA-INTEGRATION.md
│       ├── 12-DRAFTS-INTEGRATION.md
│       ├── 13-N8N-WORKFLOW-SPECS.md
│       ├── 14-CONFIGURATION.md
│       ├── 15-TESTING.md
│       ├── 16-PHASE-7-THINGS.md         # NEW: Things integration
│       ├── 20-SETUP-INSTRUCTIONS.md
│       ├── 21-MIGRATION-GUIDE.md
│       └── 22-TROUBLESHOOTING.md
├── database/
├── workflows/
└── ...
```

## Maintenance Notes for Claude

**When updating status:**
1. Edit 02-CURRENT-STATUS.md to reflect completed work
2. Update phase files (03-PHASE-*.md) to mark tasks complete
3. Add completion dates and notes
4. Keep this index synchronized

**When adding features:**
1. Determine which phase they belong to
2. Update that phase file
3. Add technical details to relevant reference docs (10-15)
4. Update 02-CURRENT-STATUS.md if starting new phase

**When troubleshooting:**
1. Add solutions to 22-TROUBLESHOOTING.md
2. Link from relevant phase or technical doc
3. Include error messages and fixes

## Version History

- **2025-10-31**: Created modular structure from monolithic ROADMAP.md
- **2025-10-30**: Phase 1 completed (10 notes processed)
- **2025-10-18**: Initial roadmap created