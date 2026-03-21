import Foundation
import SQLite

enum Migration010_MemoryThreadScope {
    static func run(db: Connection) throws {
        do {
            try db.run("ALTER TABLE conversation_memories ADD COLUMN thread_id INTEGER REFERENCES threads(id)")
        } catch {
            // Column may already exist
        }
        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_thread ON conversation_memories(thread_id)")
        print("Migration 010: Added thread_id to conversation_memories")
    }
}
