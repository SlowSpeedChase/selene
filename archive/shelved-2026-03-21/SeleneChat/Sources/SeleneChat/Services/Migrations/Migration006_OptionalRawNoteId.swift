import SeleneShared
// Migration006_OptionalRawNoteId.swift
// SeleneChat
//
// Phase 7.2: Allow threads without associated notes
// Makes raw_note_id nullable to support creating threads directly from projects

import Foundation
import SQLite

struct Migration006_OptionalRawNoteId {
    static func run(db: Connection) throws {
        // SQLite doesn't support ALTER COLUMN directly.
        // Recreate table with nullable raw_note_id.

        // 1. Create new table with nullable raw_note_id
        try db.run("""
            CREATE TABLE IF NOT EXISTS discussion_threads_new (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                raw_note_id INTEGER,
                thread_type TEXT NOT NULL CHECK(thread_type IN ('planning', 'followup', 'question')),
                prompt TEXT NOT NULL,
                status TEXT DEFAULT 'pending' CHECK(status IN ('pending', 'active', 'completed', 'dismissed', 'review')),
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                surfaced_at TEXT,
                completed_at TEXT,
                related_concepts TEXT,
                test_run TEXT DEFAULT NULL,
                project_id INTEGER REFERENCES projects(id),
                thread_name TEXT,
                resurface_reason TEXT,
                last_resurfaced_at TEXT,
                FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL
            )
        """)

        // 2. Copy data from old table
        try db.run("""
            INSERT INTO discussion_threads_new
            SELECT id, raw_note_id, thread_type, prompt, status, created_at,
                   surfaced_at, completed_at, related_concepts, test_run,
                   project_id, thread_name, resurface_reason, last_resurfaced_at
            FROM discussion_threads
        """)

        // 3. Drop old table
        try db.run("DROP TABLE discussion_threads")

        // 4. Rename new table
        try db.run("ALTER TABLE discussion_threads_new RENAME TO discussion_threads")

        // 5. Recreate indexes
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_threads_project
            ON discussion_threads(project_id)
        """)

        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_threads_status
            ON discussion_threads(status)
        """)

        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_discussion_threads_raw_note_id
            ON discussion_threads(raw_note_id)
        """)

        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_discussion_threads_test_run
            ON discussion_threads(test_run)
        """)

        print("Migration 006: raw_note_id is now nullable in discussion_threads")
    }
}
