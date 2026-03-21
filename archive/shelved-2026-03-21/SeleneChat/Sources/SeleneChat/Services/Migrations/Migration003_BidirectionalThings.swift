import SeleneShared
// Migration003_BidirectionalThings.swift
// SeleneChat
//
// Phase 7.2e: Bidirectional Things Flow
// Adds status tracking columns to task_links and resurface columns to discussion_threads

import Foundation
import SQLite

struct Migration003_BidirectionalThings {
    static func run(db: Connection) throws {
        // Add status tracking columns to task_links
        do {
            try db.run("ALTER TABLE task_links ADD COLUMN things_status TEXT DEFAULT 'open'")
        } catch {
            // Column may already exist
        }

        do {
            try db.run("ALTER TABLE task_links ADD COLUMN things_completed_at TEXT")
        } catch {
            // Column may already exist
        }

        do {
            try db.run("ALTER TABLE task_links ADD COLUMN last_synced_at TEXT")
        } catch {
            // Column may already exist
        }

        // Add resurface columns to discussion_threads
        do {
            try db.run("ALTER TABLE discussion_threads ADD COLUMN resurface_reason TEXT")
        } catch {
            // Column may already exist
        }

        do {
            try db.run("ALTER TABLE discussion_threads ADD COLUMN last_resurfaced_at TEXT")
        } catch {
            // Column may already exist
        }

        // Create index for faster status queries
        _ = try? db.run("CREATE INDEX IF NOT EXISTS idx_task_links_status ON task_links(things_status)")

        print("Migration 003: Bidirectional Things sync columns added")
    }
}
