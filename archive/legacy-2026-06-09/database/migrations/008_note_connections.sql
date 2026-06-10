-- Migration 008: Add note_connections table for workflow 06-connection-network
-- Created: 2025-01-01
-- Purpose: Store individual note-to-note connections based on concept/theme similarity

CREATE TABLE IF NOT EXISTS note_connections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_note_id INTEGER NOT NULL,
    target_note_id INTEGER NOT NULL,
    connection_strength REAL,
    connection_type TEXT,             -- 'concept_based' or 'theme_based'
    shared_concepts TEXT,             -- JSON array
    shared_themes TEXT,               -- JSON array
    concept_overlap_score REAL,
    theme_overlap_score REAL,
    temporal_score REAL,
    days_between INTEGER,
    discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active INTEGER DEFAULT 1,
    test_run TEXT DEFAULT NULL,       -- For test data isolation
    UNIQUE(source_note_id, target_note_id),
    FOREIGN KEY (source_note_id) REFERENCES raw_notes(id),
    FOREIGN KEY (target_note_id) REFERENCES raw_notes(id)
);

-- Indexes for efficient querying
CREATE INDEX IF NOT EXISTS idx_note_connections_source ON note_connections(source_note_id);
CREATE INDEX IF NOT EXISTS idx_note_connections_target ON note_connections(target_note_id);
CREATE INDEX IF NOT EXISTS idx_note_connections_strength ON note_connections(connection_strength);
CREATE INDEX IF NOT EXISTS idx_note_connections_test_run ON note_connections(test_run);
