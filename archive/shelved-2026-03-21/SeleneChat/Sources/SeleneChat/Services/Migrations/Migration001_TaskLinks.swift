import SeleneShared
// Migration001_TaskLinks.swift
// SeleneChat
//
// Created for Phase 7.2: SeleneChat Planning Integration
// Links Things tasks to Selene notes and planning threads.
// Things 3 remains the task database; we only store links.

import Foundation
import SQLite

struct Migration001_TaskLinks {
    static func run(db: Connection) throws {
        // Create task_links table
        try db.run("""
            CREATE TABLE IF NOT EXISTS task_links (
                things_task_id TEXT PRIMARY KEY,
                raw_note_id INTEGER,
                discussion_thread_id INTEGER,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id),
                FOREIGN KEY (discussion_thread_id) REFERENCES discussion_threads(id)
            )
        """)

        // Create indexes for efficient lookups
        try db.run("CREATE INDEX IF NOT EXISTS idx_task_links_thread ON task_links(discussion_thread_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_task_links_note ON task_links(raw_note_id)")

        print("Migration 001: task_links table created")
    }
}
