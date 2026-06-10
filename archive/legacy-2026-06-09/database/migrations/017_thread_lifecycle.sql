-- Migration 017: Thread Lifecycle
-- Expand CHECK constraints on threads.status and thread_history.change_type
-- to support archive/merge/reactivate lifecycle operations.
--
-- SQLite does not support ALTER CHECK constraints, so we recreate tables.
-- Created: 2026-02-13

-- Disable foreign keys during table recreation
PRAGMA foreign_keys = OFF;

BEGIN TRANSACTION;

-- ============================================================
-- 1. Recreate threads table with expanded status CHECK
-- ============================================================

-- Create new table with expanded CHECK constraint
CREATE TABLE threads_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    why TEXT,
    summary TEXT,
    status TEXT DEFAULT 'active',
    note_count INTEGER DEFAULT 0,
    last_activity_at TEXT,
    emotional_charge REAL,
    momentum_score REAL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'paused', 'completed', 'abandoned', 'archived', 'merged'))
);

-- Copy all existing data
INSERT INTO threads_new (id, name, why, summary, status, note_count, last_activity_at, emotional_charge, momentum_score, created_at, updated_at)
    SELECT id, name, why, summary, status, note_count, last_activity_at, emotional_charge, momentum_score, created_at, updated_at
    FROM threads;

-- Drop old table
DROP TABLE threads;

-- Rename new table
ALTER TABLE threads_new RENAME TO threads;

-- Recreate indexes for threads
CREATE INDEX idx_threads_status ON threads(status);
CREATE INDEX idx_threads_activity ON threads(last_activity_at DESC);
CREATE INDEX idx_threads_momentum ON threads(momentum_score DESC);

-- ============================================================
-- 2. Recreate thread_history table with expanded change_type CHECK
-- ============================================================

-- Create new table with expanded CHECK constraint
CREATE TABLE thread_history_new (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,
    change_type TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (trigger_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL,
    CHECK(change_type IN ('note_added', 'merged', 'split', 'renamed', 'summarized', 'created', 'archived', 'reactivated'))
);

-- Copy all existing data
INSERT INTO thread_history_new (id, thread_id, summary_before, summary_after, trigger_note_id, change_type, created_at)
    SELECT id, thread_id, summary_before, summary_after, trigger_note_id, change_type, created_at
    FROM thread_history;

-- Drop old table
DROP TABLE thread_history;

-- Rename new table
ALTER TABLE thread_history_new RENAME TO thread_history;

-- Recreate indexes for thread_history
CREATE INDEX idx_thread_history_thread ON thread_history(thread_id);

COMMIT;

-- Re-enable foreign keys
PRAGMA foreign_keys = ON;
