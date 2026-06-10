-- Migration: 015_conversation_memory.sql
-- Purpose: Create tables for conversation memory system
-- Date: 2026-02-04

-- Store raw chat history for memory extraction
CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_conversations_session ON conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at);

-- Extracted memories (facts learned from conversations)
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
);

CREATE INDEX IF NOT EXISTS idx_memories_type ON conversation_memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_memories_confidence ON conversation_memories(confidence);
CREATE INDEX IF NOT EXISTS idx_memories_last_accessed ON conversation_memories(last_accessed);
