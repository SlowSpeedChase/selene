import SeleneShared
// Migration008_ConversationMemory.swift
// SeleneChat
//
// Conversation Memory System
// Creates tables for storing conversation history and extracted memories

import Foundation
import SQLite

struct Migration008_ConversationMemory {
    static func run(db: Connection) throws {
        // Create conversations table
        try db.run("""
            CREATE TABLE IF NOT EXISTS conversations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
                content TEXT NOT NULL,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)

        try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at)")

        // Create conversation_memories table
        try db.run("""
            CREATE TABLE IF NOT EXISTS conversation_memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                content TEXT NOT NULL,
                source_session_id TEXT,
                embedding BLOB,
                memory_type TEXT CHECK(memory_type IN ('preference', 'fact', 'pattern', 'context')),
                confidence REAL DEFAULT 1.0,
                last_accessed TEXT,
                created_at TEXT DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
        """)

        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_type ON conversation_memories(memory_type)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_confidence ON conversation_memories(confidence)")
        try db.run("CREATE INDEX IF NOT EXISTS idx_memories_last_accessed ON conversation_memories(last_accessed)")

        print("Migration 008: conversations and conversation_memories tables created")
    }
}
