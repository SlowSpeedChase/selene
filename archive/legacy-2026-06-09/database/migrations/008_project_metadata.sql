-- Migration 008: Project Metadata for Things Project Grouping
-- Created: 2026-01-01
-- Phase: 7.2f.1 - Basic Project Creation

BEGIN TRANSACTION;

-- Table: project_metadata
-- Stores Selene's metadata about Things projects
CREATE TABLE IF NOT EXISTS project_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Things integration
    things_project_id TEXT NOT NULL UNIQUE,
    project_name TEXT NOT NULL,

    -- Concept linkage
    primary_concept TEXT NOT NULL,
    related_concepts TEXT,  -- JSON array of secondary concepts

    -- ADHD optimization
    energy_profile TEXT CHECK(energy_profile IN ('high', 'mixed', 'low')),
    total_estimated_minutes INTEGER DEFAULT 0,

    -- Counts (denormalized for quick access)
    task_count INTEGER DEFAULT 0,
    completed_task_count INTEGER DEFAULT 0,

    -- Lifecycle
    status TEXT DEFAULT 'active'
        CHECK(status IN ('active', 'completed', 'archived')),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    last_synced_at TEXT,

    -- Things state (cached)
    things_status TEXT DEFAULT 'active'
        CHECK(things_status IN ('active', 'completed', 'canceled')),

    -- Test isolation
    test_run TEXT
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_project_metadata_concept ON project_metadata(primary_concept);
CREATE INDEX IF NOT EXISTS idx_project_metadata_things_id ON project_metadata(things_project_id);
CREATE INDEX IF NOT EXISTS idx_project_metadata_status ON project_metadata(status);
CREATE INDEX IF NOT EXISTS idx_project_metadata_test_run ON project_metadata(test_run);

COMMIT;
