import SeleneShared
// Migration002_PlanningInbox.swift
// SeleneChat
//
// Created for Phase 7: Planning Inbox Redesign
// Creates projects table and adds inbox columns to raw_notes

import Foundation
import SQLite

struct Migration002_PlanningInbox {
    static func run(db: Connection) throws {
        // Create projects table
        try db.run("""
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
            )
        """)

        try db.run("CREATE INDEX IF NOT EXISTS idx_projects_status ON projects(status)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_projects_test_run ON projects(test_run)")

        // Create project_notes junction table
        try db.run("""
            CREATE TABLE IF NOT EXISTS project_notes (
                project_id INTEGER NOT NULL,
                raw_note_id INTEGER NOT NULL,
                attached_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (project_id, raw_note_id),
                FOREIGN KEY (project_id) REFERENCES projects(id),
                FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
            )
        """)

        try db.run("CREATE INDEX IF NOT EXISTS idx_project_notes_project ON project_notes(project_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_project_notes_note ON project_notes(raw_note_id)")

        // Add inbox columns to raw_notes (ignore if already exist)
        do {
            try db.run("ALTER TABLE raw_notes ADD COLUMN inbox_status TEXT DEFAULT 'pending'")
        } catch {
            // Column may already exist
        }

        do {
            try db.run("ALTER TABLE raw_notes ADD COLUMN suggested_type TEXT")
        } catch {
            // Column may already exist
        }

        do {
            try db.run("ALTER TABLE raw_notes ADD COLUMN suggested_project_id INTEGER")
        } catch {
            // Column may already exist
        }

        try db.run("CREATE INDEX IF NOT EXISTS idx_raw_notes_inbox_status ON raw_notes(inbox_status)")

        print("Migration 002: Planning inbox tables created")
    }
}
