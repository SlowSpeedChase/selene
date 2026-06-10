# Database Schema Context

## Purpose

SQLite database schema for Selene note management system. Stores raw notes, LLM-processed data, sentiment analysis, pattern detection, and connection networks. Designed for test data isolation and temporal tracking.

## Tech Stack

- SQLite 3 (embedded relational database)
- better-sqlite3 (Node.js driver for n8n)
- SQLite.swift (Swift driver for SeleneChat)
- SQL migrations for schema changes

## Key Files

- schema.sql (8 tables) - Complete database schema
- migrations/ - Schema version control
- README.md - Schema documentation

## Database Structure

### Core Tables (8 total)

1. **raw_notes** - Ingested notes from Drafts
2. **processed_notes** - LLM-extracted concepts/themes
3. **sentiment_history** - Emotional tone and energy levels
4. **detected_patterns** - Recurring themes over time
5. **pattern_reports** - Pattern summaries
6. **network_analysis_history** - Note connections
7. **test_table** - Development/testing
8. **(note_connections)** - Planned for future

## Schema Patterns

### Test Data Isolation (CRITICAL)
```sql
-- All tables include test_run column
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    test_run TEXT,  -- NULL = production, otherwise test-run-YYYYMMDD-HHMMSS
    ...
);

-- Query production data only
SELECT * FROM raw_notes WHERE test_run IS NULL;

-- Query test data
SELECT * FROM raw_notes WHERE test_run = 'test-run-20251124-120000';

-- Cleanup test data
DELETE FROM raw_notes WHERE test_run = 'test-run-20251124-120000';
```

### Temporal Tracking
```sql
-- Standard timestamp columns
created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
processed_at DATETIME,
updated_at DATETIME
```

### Status Tracking
```sql
-- Workflow state management
status TEXT,  -- 'pending', 'processing', 'completed', 'failed'

-- Enables resumption after failures
WHERE status = 'pending' OR status = 'failed'
```

### JSON Storage
```sql
-- Store complex data as JSON TEXT
concepts TEXT,          -- ["concept1", "concept2", ...]
themes TEXT,            -- ["theme1", "theme2"]
sentiment_data TEXT     -- {"sentiment": "positive", ...}

-- Parse in application code
JSON.parse(row.concepts)
```

## raw_notes Table

### Purpose
Initial storage for all captured notes. Source of truth.

### Schema
```sql
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,  -- SHA256 for deduplication
    source_uuid TEXT,                    -- UUID from Drafts
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    status TEXT,                         -- Processing workflow state
    test_run TEXT
);

CREATE INDEX idx_raw_notes_hash ON raw_notes(content_hash);
CREATE INDEX idx_raw_notes_created ON raw_notes(created_at);
```

### Key Patterns
- `content_hash` UNIQUE prevents duplicates
- `source_uuid` tracks individual Drafts
- `status` enables workflow coordination

## processed_notes Table

### Purpose
LLM-extracted semantic data (concepts, themes, keywords).

### Schema
```sql
CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,                   -- JSON array
    themes TEXT,                     -- JSON array
    keywords TEXT,                   -- JSON array
    processed_at DATETIME,
    sentiment_analyzed INTEGER DEFAULT 0,  -- Boolean flag
    test_run TEXT,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);

CREATE INDEX idx_processed_raw_id ON processed_notes(raw_note_id);
CREATE INDEX idx_processed_sentiment ON processed_notes(sentiment_analyzed);
```

## sentiment_history Table

### Purpose
Emotional tone and energy level tracking for ADHD users.

### Schema
```sql
CREATE TABLE sentiment_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_id INTEGER NOT NULL,
    sentiment_data TEXT,                 -- Full JSON
    overall_sentiment TEXT,              -- 'positive', 'negative', 'neutral'
    sentiment_score REAL,                -- -1.0 to 1.0
    emotional_tone TEXT,
    energy_level TEXT,                   -- 'high', 'medium', 'low' (ADHD focus)
    analysis_confidence REAL,            -- 0.0 to 1.0
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    test_run TEXT,
    FOREIGN KEY (note_id) REFERENCES processed_notes(id)
);

CREATE INDEX idx_sentiment_note ON sentiment_history(note_id);
CREATE INDEX idx_sentiment_energy ON sentiment_history(energy_level);
```

### ADHD Features
- `energy_level` tracks productive vs. rest periods
- `sentiment_score` enables mood trend analysis
- `created_at` allows temporal pattern detection

## detected_patterns Table

### Purpose
Track recurring themes and concept clusters over time.

### Schema
```sql
CREATE TABLE detected_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_type TEXT,               -- 'theme_trend', 'concept_cluster'
    pattern_data TEXT,               -- JSON details
    frequency INTEGER,
    first_seen DATETIME,
    last_seen DATETIME,
    confidence_score REAL,
    test_run TEXT
);
```

## network_analysis_history Table

### Purpose
Note connections based on concept similarity.

### Schema
```sql
CREATE TABLE network_analysis_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_note_id INTEGER NOT NULL,
    to_note_id INTEGER NOT NULL,
    connection_strength REAL,        -- 0.0 to 1.0 (Jaccard similarity)
    shared_concepts TEXT,            -- JSON array of overlapping concepts
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    test_run TEXT,
    FOREIGN KEY (from_note_id) REFERENCES raw_notes(id),
    FOREIGN KEY (to_note_id) REFERENCES raw_notes(id)
);

CREATE INDEX idx_network_from ON network_analysis_history(from_note_id);
CREATE INDEX idx_network_to ON network_analysis_history(to_note_id);
```

## Common Query Patterns

### Join Notes with Processing Data
```sql
SELECT
    r.id,
    r.content,
    r.created_at,
    p.concepts,
    p.themes,
    s.energy_level,
    s.overall_sentiment
FROM raw_notes r
LEFT JOIN processed_notes p ON r.id = p.raw_note_id
LEFT JOIN sentiment_history s ON p.id = s.note_id
WHERE r.test_run IS NULL  -- Production only
ORDER BY r.created_at DESC
LIMIT 10;
```

### Find Unprocessed Notes
```sql
SELECT r.*
FROM raw_notes r
LEFT JOIN processed_notes p ON r.id = p.raw_note_id
WHERE p.id IS NULL
  AND r.test_run IS NULL
ORDER BY r.created_at ASC;
```

### Energy Level Statistics
```sql
SELECT
    DATE(created_at) as date,
    energy_level,
    COUNT(*) as count
FROM sentiment_history
WHERE test_run IS NULL
GROUP BY DATE(created_at), energy_level
ORDER BY date DESC;
```

## Migrations

### Migration Pattern
```sql
-- migrations/001_add_source_uuid.sql
ALTER TABLE raw_notes ADD COLUMN source_uuid TEXT;

-- migrations/002_add_sentiment_analyzed_flag.sql
ALTER TABLE processed_notes ADD COLUMN sentiment_analyzed INTEGER DEFAULT 0;
```

### Apply Migrations
```bash
sqlite3 data/selene.db < database/migrations/001_add_source_uuid.sql
```

## Do NOT

- **NEVER delete test_run column** - Critical for test isolation
- **NEVER use CASCADE DELETE** - Explicitly manage relationships
- **NEVER skip indexes** - Performance degrades on large datasets
- **NEVER store secrets** - Database may be backed up/shared
- **NEVER use TEXT for booleans** - Use INTEGER (0/1)
- **NEVER skip FOREIGN KEY constraints** - Maintains data integrity

## Backup and Restore

### Backup
```bash
# Full database backup
sqlite3 data/selene.db ".backup data/selene-backup.db"

# Export as SQL
sqlite3 data/selene.db .dump > selene-backup.sql
```

### Restore
```bash
# From backup file
cp data/selene-backup.db data/selene.db

# From SQL dump
sqlite3 data/selene.db < selene-backup.sql
```

## Performance Optimization

### Indexing Strategy
- Primary keys: Automatic index
- Foreign keys: Manual index required
- High-frequency WHERE clauses: Add index
- JOIN columns: Add index

### Query Optimization
```sql
-- Use EXPLAIN QUERY PLAN to analyze
EXPLAIN QUERY PLAN
SELECT * FROM raw_notes WHERE created_at > '2025-01-01';

-- Add index if table scan detected
CREATE INDEX idx_raw_notes_created ON raw_notes(created_at);
```

## Related Context

@database/schema.sql
@database/migrations/
@workflows/01-ingestion/CLAUDE.md
@workflows/02-llm-processing/CLAUDE.md
@SeleneChat/Sources/Services/CLAUDE.md
