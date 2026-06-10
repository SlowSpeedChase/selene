-- Migration: 013_thread_system.sql
-- Purpose: Create tables for the Thread System (semantic embeddings, associations, threads)
-- Story: US-040
-- Date: 2026-01-04

-- Vector embedding for each note
-- Stores 768-dimensional vectors from nomic-embed-text model
CREATE TABLE IF NOT EXISTS note_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,  -- JSON array of floats (768 dimensions)
    model_version TEXT NOT NULL,  -- Track which model generated it (e.g., 'nomic-embed-text')
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);

-- Note-to-note similarity links
-- Stores pairwise cosine similarity between notes above threshold
CREATE TABLE IF NOT EXISTS note_associations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    similarity_score REAL NOT NULL,  -- 0.0 to 1.0 (cosine similarity)
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id),
    CHECK(note_a_id < note_b_id),  -- Ensure consistent ordering (a < b)
    CHECK(similarity_score >= 0.0 AND similarity_score <= 1.0)
);

-- Threads (emergent clusters of related thinking)
-- A thread is a collection of semantically related notes that form a line of thinking
CREATE TABLE IF NOT EXISTS threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    why TEXT,  -- The underlying motivation/goal
    summary TEXT,
    status TEXT DEFAULT 'active',  -- active, paused, completed, abandoned
    note_count INTEGER DEFAULT 0,
    last_activity_at TEXT,
    emotional_charge REAL,  -- Aggregate sentiment intensity
    momentum_score REAL,  -- Calculated from recent activity
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'paused', 'completed', 'abandoned'))
);

-- Links between threads and notes (many-to-many)
CREATE TABLE IF NOT EXISTS thread_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    added_at TEXT DEFAULT CURRENT_TIMESTAMP,
    relevance_score REAL,  -- How central is this note to the thread (0.0 to 1.0)
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(thread_id, raw_note_id)
);

-- Thread history for tracking evolution
-- Records changes to threads over time for user insight
CREATE TABLE IF NOT EXISTS thread_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,  -- What note caused this update
    change_type TEXT NOT NULL,  -- 'note_added', 'merged', 'split', 'renamed', 'summarized'
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (trigger_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL,
    CHECK(change_type IN ('note_added', 'merged', 'split', 'renamed', 'summarized', 'created'))
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_embeddings_note ON note_embeddings(raw_note_id);
CREATE INDEX IF NOT EXISTS idx_associations_a ON note_associations(note_a_id);
CREATE INDEX IF NOT EXISTS idx_associations_b ON note_associations(note_b_id);
CREATE INDEX IF NOT EXISTS idx_associations_score ON note_associations(similarity_score DESC);
CREATE INDEX IF NOT EXISTS idx_thread_notes_thread ON thread_notes(thread_id);
CREATE INDEX IF NOT EXISTS idx_thread_notes_note ON thread_notes(raw_note_id);
CREATE INDEX IF NOT EXISTS idx_threads_status ON threads(status);
CREATE INDEX IF NOT EXISTS idx_threads_activity ON threads(last_activity_at DESC);
CREATE INDEX IF NOT EXISTS idx_threads_momentum ON threads(momentum_score DESC);
CREATE INDEX IF NOT EXISTS idx_thread_history_thread ON thread_history(thread_id);
