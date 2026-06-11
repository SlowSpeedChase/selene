-- 018_thread_activity.sql
-- Records thread activity events for momentum calculation.
-- Task completions and note additions are tracked here so
-- reconsolidate-threads.ts can factor them into momentum scores.

CREATE TABLE IF NOT EXISTS thread_activity (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    activity_type TEXT NOT NULL CHECK(activity_type IN ('note_added', 'task_completed')),
    occurred_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_thread_activity_thread ON thread_activity(thread_id);
CREATE INDEX IF NOT EXISTS idx_thread_activity_recent ON thread_activity(occurred_at);
