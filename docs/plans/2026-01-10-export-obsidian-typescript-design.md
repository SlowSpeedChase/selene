# Export Obsidian TypeScript Workflow Design

**Status:** Approved
**Date:** 2026-01-10
**Author:** Claude (with user input)

## Overview

Rewrite the Python Obsidian export script (`scripts/obsidian_export.py`) as a TypeScript workflow with full feature parity, scheduled via launchd and triggerable via HTTP endpoint.

## Requirements

- **Full feature parity** with Python script
- **Hourly schedule** via launchd
- **HTTP trigger** for manual export from Obsidian

## Architecture

### Files

| File | Purpose |
|------|---------|
| `src/workflows/export-obsidian.ts` | Core export logic |
| `src/routes/export-obsidian.ts` | HTTP endpoint `/webhook/api/export-obsidian` |
| `launchd/com.selene.export-obsidian.plist` | Hourly scheduled job |

### Flow

```
┌─────────────────────────────────────────────────────────┐
│ Triggers                                                │
│  • launchd (hourly)  →  npx ts-node export-obsidian.ts │
│  • HTTP POST         →  /webhook/api/export-obsidian    │
└───────────────────────────┬─────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────┐
│ exportObsidian()                                        │
│  1. Query notes (exported_to_obsidian = 0, processed)  │
│  2. For each note:                                      │
│     - Generate ADHD markdown                            │
│     - Write to 4 locations                              │
│     - Create concept hub if missing                     │
│     - Mark exported in DB                               │
└─────────────────────────────────────────────────────────┘
```

## Database Query

```sql
SELECT
  rn.id, rn.title, rn.content, rn.created_at, rn.tags, rn.word_count,
  pn.concepts, pn.primary_theme, pn.secondary_themes,
  pn.overall_sentiment, pn.sentiment_score, pn.emotional_tone,
  pn.energy_level, pn.sentiment_data
FROM raw_notes rn
JOIN processed_notes pn ON rn.id = pn.raw_note_id
WHERE rn.exported_to_obsidian = 0
  AND rn.status = 'processed'
  AND pn.sentiment_analyzed = 1
ORDER BY rn.created_at DESC
LIMIT 50
```

## TypeScript Interface

```typescript
interface ExportableNote {
  id: number;
  title: string;
  content: string;
  created_at: string;
  tags: string | null;
  word_count: number;
  concepts: string | null;         // JSON array
  primary_theme: string;
  secondary_themes: string | null; // JSON array
  overall_sentiment: string;
  sentiment_score: number | null;
  emotional_tone: string;
  energy_level: string;
  sentiment_data: string | null;   // JSON object with adhd_markers
}
```

## Output Locations

4 paths per note:

```
vault/Selene/
├── Timeline/2026/01/2026-01-10-my-note.md
├── By-Concept/productivity/2026-01-10-my-note.md
├── By-Theme/work/2026-01-10-my-note.md
├── By-Energy/high/2026-01-10-my-note.md
└── Concepts/productivity.md  (hub page, created once)
```

## ADHD Markdown Format

### Frontmatter

```yaml
---
title: "Note title"
date: 2026-01-10
time: "14:30"
day: Friday
theme: productivity
energy: high
mood: focused
sentiment: positive
sentiment_score: 0.85
concepts: [productivity, planning]
tags: [energy-high, mood-focused, sentiment-positive]
adhd_markers:
  overwhelm: false
  hyperfocus: true
  executive_dysfunction: false
stress: false
action_items: 3
reading_time: 2
word_count: 387
source: Selene
automated: true
---
```

### Body Sections

| Section | Content |
|---------|---------|
| Status at a Glance | Emoji table: Energy, Mood, Sentiment, ADHD markers |
| Quick Context | TL;DR box with reading time, brain state |
| Action Items | Extracted TODOs as checkboxes |
| Full Content | Original note text |
| ADHD Insights | Energy interpretation, emotional analysis, context clues |
| Processing Metadata | Word count, confidence, related notes prompt |

### Action Item Extraction

3 patterns (same as Python):
1. `- [ ] task` or `- [x] task` (checkboxes)
2. `TODO:`, `TASK:`, `ACTION:` prefixes
3. "need to", "should", "must", "have to" phrases

## HTTP Endpoint

```typescript
// POST /webhook/api/export-obsidian
// Optional body: { noteId?: number }

// Response:
{
  success: true,
  exported_count: 12,
  message: "Exported 12 notes to Obsidian"
}
```

## Launchd Configuration

| Setting | Value |
|---------|-------|
| Label | `com.selene.export-obsidian` |
| Schedule | Hourly (`:00` of each hour) |
| Command | `npx ts-node src/workflows/export-obsidian.ts` |
| Working Directory | `/Users/chaseeasterling/selene` |
| Logs | `logs/export-obsidian.out.log`, `logs/export-obsidian.err.log` |

## Obsidian Trigger Options

1. **Commander plugin** - Button running `curl -X POST http://localhost:5678/webhook/api/export-obsidian`
2. **Templater** - Template with shell command
3. **QuickAdd** - Macro with shell execution

## Implementation Order

1. Create `src/workflows/export-obsidian.ts` with all ADHD markdown logic
2. Create `src/routes/export-obsidian.ts` and register in server
3. Create `launchd/com.selene.export-obsidian.plist`
4. Test manually: `npx ts-node src/workflows/export-obsidian.ts`
5. Install launchd agent: `./scripts/install-launchd.sh`

## Files to Create/Modify

| File | Action | Lines (est.) |
|------|--------|--------------|
| `src/workflows/export-obsidian.ts` | Create | ~350 |
| `src/routes/export-obsidian.ts` | Create | ~40 |
| `src/server.ts` | Modify | +3 |
| `launchd/com.selene.export-obsidian.plist` | Create | ~30 |
