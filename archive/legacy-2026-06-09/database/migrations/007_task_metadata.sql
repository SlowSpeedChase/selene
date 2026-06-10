-- Migration 007: Task Metadata for Things Integration
-- Created: 2025-11-25
-- Phase: 7.1 - Task Extraction Foundation

BEGIN TRANSACTION;

-- Table: task_metadata
-- Stores relationship between Selene notes and Things tasks
-- Plus ADHD-optimized enrichment data
CREATE TABLE IF NOT EXISTS task_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Link to source note
    raw_note_id INTEGER NOT NULL,

    -- Things integration
    things_task_id TEXT NOT NULL UNIQUE, -- Things UUID from MCP
    things_project_id TEXT, -- NULL = inbox, otherwise project UUID

    -- ADHD-optimized enrichment (from Selene LLM analysis)
    energy_required TEXT CHECK(energy_required IN ('high', 'medium', 'low')),
    estimated_minutes INTEGER CHECK(estimated_minutes IN (5, 15, 30, 60, 120, 240)),
    related_concepts TEXT, -- JSON array of concept names
    related_themes TEXT, -- JSON array of theme names
    overwhelm_factor INTEGER CHECK(overwhelm_factor BETWEEN 1 AND 10),

    -- Task metadata extracted by LLM
    task_type TEXT CHECK(task_type IN ('action', 'decision', 'research', 'communication', 'learning', 'planning')),
    context_tags TEXT, -- JSON array: ["work", "personal", "urgent", "creative"]

    -- Timestamps
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    synced_at TEXT, -- Last time we read status from Things
    completed_at TEXT, -- When task was completed (from Things)

    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_task_metadata_note ON task_metadata(raw_note_id);
CREATE INDEX IF NOT EXISTS idx_task_metadata_things_id ON task_metadata(things_task_id);
CREATE INDEX IF NOT EXISTS idx_task_metadata_energy ON task_metadata(energy_required);
CREATE INDEX IF NOT EXISTS idx_task_metadata_completed ON task_metadata(completed_at);

-- Extend existing tables
ALTER TABLE raw_notes ADD COLUMN tasks_extracted BOOLEAN DEFAULT 0;
ALTER TABLE raw_notes ADD COLUMN tasks_extracted_at TEXT;

ALTER TABLE processed_notes ADD COLUMN things_integration_status TEXT
    CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))
    DEFAULT 'pending';

-- Table: integration_logs
-- Track workflow execution and errors
CREATE TABLE IF NOT EXISTS integration_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow TEXT NOT NULL,
    event TEXT NOT NULL,
    raw_note_id INTEGER,
    success BOOLEAN NOT NULL DEFAULT 1,
    error_message TEXT,
    timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
    metadata TEXT -- JSON for additional context
);

CREATE INDEX IF NOT EXISTS idx_integration_logs_workflow ON integration_logs(workflow);
CREATE INDEX IF NOT EXISTS idx_integration_logs_timestamp ON integration_logs(timestamp);
CREATE INDEX IF NOT EXISTS idx_integration_logs_success ON integration_logs(success);

COMMIT;
