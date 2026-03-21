import SeleneShared
// Migration005_ProjectThreads.swift
// SeleneChat
//
// Phase 7.2: Planning Tab Redesign
// Adds project_id and thread_name to discussion_threads
// Creates system Scratch Pad project

import Foundation
import SQLite

struct Migration005_ProjectThreads {
    static func run(db: Connection) throws {
        // Add project_id column (nullable for migration, will default to Scratch Pad)
        try db.run("""
            ALTER TABLE discussion_threads ADD COLUMN project_id INTEGER
            REFERENCES projects(id)
        """)

        // Add thread_name column (auto-generated from first message)
        try db.run("""
            ALTER TABLE discussion_threads ADD COLUMN thread_name TEXT
        """)

        // Create index for quick project->threads lookup
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_threads_project
            ON discussion_threads(project_id)
        """)

        // Add is_system column to projects if not exists
        do {
            try db.run("ALTER TABLE projects ADD COLUMN is_system INTEGER DEFAULT 0")
        } catch {
            // Column may already exist
        }

        // Create system Scratch Pad project (is_system=1)
        try db.run("""
            INSERT OR IGNORE INTO projects (name, status, is_system, created_at, last_active_at)
            VALUES ('Scratch Pad', 'active', 1, datetime('now'), datetime('now'))
        """)

        // Get the Scratch Pad project ID
        let scratchPadId = try db.scalar(
            "SELECT id FROM projects WHERE is_system = 1 LIMIT 1"
        ) as? Int64

        // Migrate existing orphan threads to Scratch Pad
        if let scratchPadId = scratchPadId {
            try db.run("""
                UPDATE discussion_threads
                SET project_id = \(scratchPadId)
                WHERE project_id IS NULL
            """)
        }

        print("Migration 005: project_id added to discussion_threads, Scratch Pad created")
    }
}
