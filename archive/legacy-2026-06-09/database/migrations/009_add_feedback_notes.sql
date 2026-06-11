-- Migration: Add feedback_notes table for product feedback capture
-- Created: 2025-12-31
-- Purpose: Store #selene-feedback tagged notes for backlog generation

CREATE TABLE IF NOT EXISTS feedback_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME,
    user_story TEXT,
    theme TEXT,
    cluster_id INTEGER,
    priority INTEGER DEFAULT 1,
    mention_count INTEGER DEFAULT 1,
    status TEXT DEFAULT 'open',
    implemented_pr TEXT,
    implemented_at DATETIME,
    test_run TEXT DEFAULT NULL,
    processing_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_feedback_theme ON feedback_notes(theme);
CREATE INDEX IF NOT EXISTS idx_feedback_status ON feedback_notes(status);
CREATE INDEX IF NOT EXISTS idx_feedback_cluster ON feedback_notes(cluster_id);
CREATE INDEX IF NOT EXISTS idx_feedback_test_run ON feedback_notes(test_run);
