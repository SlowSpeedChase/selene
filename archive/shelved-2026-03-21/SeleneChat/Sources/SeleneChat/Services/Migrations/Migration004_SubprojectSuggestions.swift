import SeleneShared
// Migration004_SubprojectSuggestions.swift
// SeleneChat
//
// Phase 7.2f: Sub-Project Suggestions
// Creates subproject_suggestions table for storing AI-detected project clustering opportunities

import Foundation
import SQLite

struct Migration004_SubprojectSuggestions {
    static func run(db: Connection) throws {
        // Create subproject_suggestions table
        try db.run("""
            CREATE TABLE IF NOT EXISTS subproject_suggestions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,

                -- Source project
                source_project_id TEXT NOT NULL,  -- things_project_id

                -- Suggested sub-project concept
                suggested_concept TEXT NOT NULL,
                suggested_name TEXT,  -- AI-generated or null

                -- Tasks that would move
                task_count INTEGER NOT NULL,
                task_ids TEXT NOT NULL,  -- JSON array of things_task_ids

                -- Status
                status TEXT NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending', 'approved', 'dismissed')),

                -- Result (if approved)
                created_project_id TEXT,  -- things_project_id of new project

                -- Timestamps
                detected_at TEXT DEFAULT CURRENT_TIMESTAMP,
                actioned_at TEXT,

                -- Prevent duplicate suggestions
                UNIQUE(source_project_id, suggested_concept)
            )
        """)

        // Index for quick lookups
        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_subproject_suggestions_status
            ON subproject_suggestions(status)
        """)

        try db.run("""
            CREATE INDEX IF NOT EXISTS idx_subproject_suggestions_source
            ON subproject_suggestions(source_project_id)
        """)

        print("Migration 004: subproject_suggestions table created")
    }
}
