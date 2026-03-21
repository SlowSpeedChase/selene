import SeleneShared
// Migration009_ThreadTasks.swift
// SeleneChat
//
// Links Things tasks to semantic threads for workspace view

import Foundation
import SQLite

struct Migration009_ThreadTasks {
    static func run(db: Connection) throws {
        // Create thread_tasks table
        try db.run("""
            CREATE TABLE IF NOT EXISTS thread_tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                thread_id INTEGER NOT NULL,
                things_task_id TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                completed_at TEXT,
                FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
                UNIQUE(thread_id, things_task_id)
            )
        """)

        // Index for querying tasks by thread
        try db.run("CREATE INDEX IF NOT EXISTS idx_thread_tasks_thread ON thread_tasks(thread_id)")

        // Index for looking up thread by Things task ID (for sync)
        try db.run("CREATE INDEX IF NOT EXISTS idx_thread_tasks_things ON thread_tasks(things_task_id)")

        print("Migration 009: thread_tasks table created")
    }
}
