-- 011_planning_inbox.sql
-- Phase 7: Planning Inbox Redesign
-- Creates projects table, project_notes junction, and modifies raw_notes

BEGIN TRANSACTION;

-- Projects table for Active/Parked structure
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    status TEXT DEFAULT 'parked'
        CHECK(status IN ('active', 'parked', 'completed')),
    primary_concept TEXT,
    things_project_id TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_active_at DATETIME,
    completed_at DATETIME,
    test_run TEXT DEFAULT NULL
);

CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_projects_test_run ON projects(test_run);

-- Junction table linking projects to notes
CREATE TABLE IF NOT EXISTS project_notes (
    project_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    attached_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (project_id, raw_note_id),
    FOREIGN KEY (project_id) REFERENCES projects(id),
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);

CREATE INDEX IF NOT EXISTS idx_project_notes_project ON project_notes(project_id);
CREATE INDEX IF NOT EXISTS idx_project_notes_note ON project_notes(raw_note_id);

-- Add inbox tracking columns to raw_notes
-- inbox_status: pending (new), triaged (processed), archived (hidden)
-- suggested_type: AI hint for triage (quick_task, relates_to_project, new_project, reflection)
-- suggested_project_id: If relates_to_project, which project

ALTER TABLE raw_notes ADD COLUMN inbox_status TEXT DEFAULT 'pending'
    CHECK(inbox_status IN ('pending', 'triaged', 'archived'));

ALTER TABLE raw_notes ADD COLUMN suggested_type TEXT
    CHECK(suggested_type IN ('quick_task', 'relates_to_project', 'new_project', 'reflection'));

ALTER TABLE raw_notes ADD COLUMN suggested_project_id INTEGER
    REFERENCES projects(id);

CREATE INDEX IF NOT EXISTS idx_raw_notes_inbox_status ON raw_notes(inbox_status);

COMMIT;
