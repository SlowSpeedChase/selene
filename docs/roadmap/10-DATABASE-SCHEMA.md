# Database Schema Reference

**Database:** SQLite
**Location:** `/selene/data/selene.db`
**Schema Source:** Copied from Python project `/selene/data/schema.sql`

## Overview

The Selene database uses SQLite with a well-designed schema for storing notes, analysis results, and detected patterns. The schema was designed for the Python version and works perfectly with n8n.

## Core Tables

### raw_notes

Stores incoming notes from Drafts before LLM processing.

```sql
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    uuid TEXT UNIQUE NOT NULL,
    title TEXT,
    content TEXT NOT NULL,
    tags TEXT,  -- JSON array
    created_at TEXT NOT NULL,
    received_at TEXT DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'processing', 'processed', 'failed')),
    error_message TEXT
);

CREATE INDEX idx_raw_notes_status ON raw_notes(status);
CREATE INDEX idx_raw_notes_created ON raw_notes(created_at);
```

**Fields:**
- `uuid` - Drafts unique identifier
- `title` - Note title (optional)
- `content` - Note body text
- `tags` - JSON array of tags from Drafts
- `created_at` - When note was created in Drafts
- `received_at` - When n8n received the note
- `status` - Processing state: pending → processing → processed/failed
- `error_message` - If processing failed, why

**Common Queries:**
```sql
-- Get next pending note
SELECT * FROM raw_notes WHERE status = 'pending' ORDER BY created_at ASC LIMIT 1;

-- Check for stuck notes
SELECT * FROM raw_notes WHERE status = 'pending' AND created_at < datetime('now', '-5 minutes');

-- Count by status
SELECT status, COUNT(*) FROM raw_notes GROUP BY status;
```

### processed_notes

Stores LLM analysis results after Ollama processing.

```sql
CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,  -- JSON array
    themes TEXT,  -- JSON array
    entities TEXT,  -- JSON object
    summary TEXT,
    overall_sentiment TEXT,  -- 'positive', 'negative', 'neutral'
    sentiment_score REAL,  -- 0.0 to 1.0
    emotional_tone TEXT,  -- 'excited', 'calm', 'anxious', etc.
    energy_level TEXT,  -- 'high', 'medium', 'low'
    confidence_score REAL,  -- 0.0 to 1.0
    processed_at TEXT DEFAULT CURRENT_TIMESTAMP,
    exported INTEGER DEFAULT 0,  -- 0 = not exported, 1 = exported to Obsidian
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);

CREATE INDEX idx_processed_notes_exported ON processed_notes(exported);
CREATE INDEX idx_processed_notes_date ON processed_notes(processed_at);
```

**Fields:**
- `raw_note_id` - Links to `raw_notes.id`
- `concepts` - JSON array of extracted concepts: `["concept1", "concept2"]`
- `themes` - JSON array of themes: `["theme1", "theme2"]`
- `entities` - JSON object: `{"people": [], "places": [], "organizations": [], "dates": []}`
- `summary` - Short summary (optional, not used in Phase 1)
- `overall_sentiment` - positive/negative/neutral
- `sentiment_score` - 0.0 (negative) to 1.0 (positive)
- `emotional_tone` - Description like "excited", "anxious", "calm"
- `energy_level` - high/medium/low
- `confidence_score` - Average confidence of LLM analysis
- `processed_at` - When Ollama processed the note
- `exported` - Whether exported to Obsidian

**Common Queries:**
```sql
-- Get unexported notes for Obsidian export
SELECT * FROM processed_notes WHERE exported = 0 ORDER BY processed_at ASC LIMIT 50;

-- Join with raw notes to get full data
SELECT
  rn.title,
  rn.content,
  pn.concepts,
  pn.themes,
  pn.overall_sentiment,
  pn.confidence_score
FROM processed_notes pn
JOIN raw_notes rn ON pn.raw_note_id = rn.id
ORDER BY pn.processed_at DESC
LIMIT 10;

-- Average confidence score
SELECT AVG(confidence_score) FROM processed_notes;

-- Sentiment breakdown
SELECT overall_sentiment, COUNT(*) FROM processed_notes GROUP BY overall_sentiment;
```

### themes

Tracks theme usage across notes for pattern detection.

```sql
CREATE TABLE themes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    note_count INTEGER DEFAULT 0,
    first_seen TEXT DEFAULT CURRENT_TIMESTAMP,
    last_seen TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_themes_count ON themes(note_count);
```

**Fields:**
- `name` - Theme name (e.g., "project-planning")
- `description` - Optional description
- `note_count` - How many notes have this theme
- `first_seen` - First occurrence
- `last_seen` - Most recent occurrence

**Usage:**
- Phase 3 (pattern detection) updates this table
- Used to identify trending themes

### concepts

Tracks concept usage across notes.

```sql
CREATE TABLE concepts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    note_count INTEGER DEFAULT 0,
    first_seen TEXT DEFAULT CURRENT_TIMESTAMP,
    last_seen TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_concepts_count ON concepts(note_count);
```

Similar to themes table, tracks concept usage over time.

### connections

Links between notes (conceptual relationships).

```sql
CREATE TABLE connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id_1 INTEGER NOT NULL,
    note_id_2 INTEGER NOT NULL,
    connection_type TEXT,  -- 'theme', 'concept', 'entity'
    connection_value TEXT,  -- What connects them
    strength REAL,  -- 0.0 to 1.0
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_id_1) REFERENCES raw_notes(id),
    FOREIGN KEY (note_id_2) REFERENCES raw_notes(id)
);

CREATE INDEX idx_connections_note1 ON connections(note_id_1);
CREATE INDEX idx_connections_note2 ON connections(note_id_2);
```

**Usage:**
- Phase 3 (connection network) populates this
- Identifies notes that share concepts, themes, or entities
- Used to build knowledge graph in Obsidian

### patterns

Detected patterns and trends.

```sql
CREATE TABLE patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_type TEXT NOT NULL,  -- 'theme_trend', 'concept_cluster', 'temporal'
    pattern_data TEXT,  -- JSON object with pattern details
    time_window TEXT,  -- '7d', '30d', '90d'
    generated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    confidence REAL  -- 0.0 to 1.0
);

CREATE INDEX idx_patterns_type ON patterns(pattern_type);
CREATE INDEX idx_patterns_date ON patterns(generated_at);
```

**Usage:**
- Phase 3 (pattern detection) writes here
- Stores trending themes, concept clusters, temporal patterns
- Exported to Obsidian for visualization

## Working with JSON Fields

SQLite doesn't have native JSON type, but supports JSON functions:

### Extract Concepts
```sql
-- Get all concepts from a note
SELECT json_each.value as concept
FROM processed_notes, json_each(processed_notes.concepts)
WHERE processed_notes.id = 1;

-- Count concepts per note
SELECT id, json_array_length(concepts) as concept_count
FROM processed_notes;
```

### Extract Themes
```sql
-- Get all themes across all notes
SELECT json_each.value as theme, COUNT(*) as occurrences
FROM processed_notes, json_each(processed_notes.themes)
GROUP BY theme
ORDER BY occurrences DESC;
```

### Search by Concept
```sql
-- Find notes containing specific concept
SELECT pn.id, rn.title
FROM processed_notes pn
JOIN raw_notes rn ON pn.raw_note_id = rn.id
WHERE json_each.value = 'project-planning';
```

## Useful Queries for n8n Workflows

### Get Next Pending Note
```sql
SELECT * FROM raw_notes
WHERE status = 'pending'
ORDER BY created_at ASC
LIMIT 1;
```

### Mark Note as Processing
```sql
UPDATE raw_notes
SET status = 'processing'
WHERE id = ?;
```

### Insert Processed Results
```sql
INSERT INTO processed_notes (
  raw_note_id,
  concepts,
  themes,
  overall_sentiment,
  sentiment_score,
  emotional_tone,
  energy_level,
  confidence_score,
  processed_at
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'));
```

### Update Raw Note Status
```sql
UPDATE raw_notes
SET status = 'processed'
WHERE id = ?;
```

### Get Unexported Notes
```sql
SELECT
  pn.id,
  pn.concepts,
  pn.themes,
  pn.overall_sentiment,
  rn.title,
  rn.content,
  rn.created_at
FROM processed_notes pn
JOIN raw_notes rn ON pn.raw_note_id = rn.id
WHERE pn.exported = 0
ORDER BY pn.processed_at ASC
LIMIT 50;
```

### Mark as Exported
```sql
UPDATE processed_notes
SET exported = 1
WHERE id = ?;
```

## Database Maintenance

### Backup Command
```bash
sqlite3 /selene/data/selene.db ".backup /selene/data/backups/selene-$(date +%Y%m%d).db"
```

### Vacuum (Optimize)
```bash
sqlite3 /selene/data/selene.db "VACUUM;"
```

### Check Integrity
```bash
sqlite3 /selene/data/selene.db "PRAGMA integrity_check;"
```

### View Schema
```bash
sqlite3 /selene/data/selene.db ".schema"
```

## Database Location

**Development:** `/selene/data/selene.db`
**Schema File:** `/Users/chaseeasterling/selene/database/schema.sql`

To recreate database:
```bash
cd /Users/chaseeasterling/selene
sqlite3 database/selene.db < database/schema.sql
```

## Performance Considerations

1. **Indexes** - Already created for common queries (status, dates, exported flag)
2. **JSON functions** - SQLite JSON functions are efficient but avoid in WHERE clauses when possible
3. **LIMIT** - Always use LIMIT in queries that could return many rows
4. **Transactions** - n8n SQLite node handles this automatically

## Migration Notes

This schema was copied as-is from the Python project. It's production-ready and well-designed. No changes needed for n8n usage.

**Original Location:** `/selene/data/schema.sql` (Python project)
**Current Location:** `/selene/database/schema.sql`

## Related Documentation

- [03-PHASE-1-CORE.md](./03-PHASE-1-CORE.md) - Uses raw_notes and processed_notes
- [04-PHASE-2-OBSIDIAN.md](./04-PHASE-2-OBSIDIAN.md) - Queries processed_notes for export
- [05-PHASE-3-PATTERNS.md](./05-PHASE-3-PATTERNS.md) - Uses themes, concepts, connections, patterns tables
