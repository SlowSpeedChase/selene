-- Migration 016: Thread Tasks
-- Links Things tasks to semantic threads for workspace view
-- Created: 2026-02-06

-- Table to track which Things tasks belong to which threads
CREATE TABLE IF NOT EXISTS thread_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    things_task_id TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    UNIQUE(thread_id, things_task_id)
);

-- Index for querying tasks by thread
CREATE INDEX IF NOT EXISTS idx_thread_tasks_thread ON thread_tasks(thread_id);

-- Index for looking up thread by Things task ID (for sync)
CREATE INDEX IF NOT EXISTS idx_thread_tasks_things ON thread_tasks(things_task_id);

-- Index for finding incomplete tasks
CREATE INDEX IF NOT EXISTS idx_thread_tasks_incomplete ON thread_tasks(thread_id)
    WHERE completed_at IS NULL;
