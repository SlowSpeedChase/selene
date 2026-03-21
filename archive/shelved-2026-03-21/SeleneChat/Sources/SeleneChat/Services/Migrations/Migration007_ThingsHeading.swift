import SeleneShared
// Migration007_ThingsHeading.swift
// SeleneChat
//
// Phase 7.2: Things heading support
// Adds things_heading column to task_links for tracking which heading a task was created under

import Foundation
import SQLite

struct Migration007_ThingsHeading {
    static func run(db: Connection) throws {
        // Add things_heading column to task_links
        do {
            try db.run("ALTER TABLE task_links ADD COLUMN things_heading TEXT")
        } catch {
            // Column may already exist
        }

        print("Migration 007: things_heading column added to task_links")
    }
}
