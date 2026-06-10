-- Migration: Add chat session storage
-- Date: 2025-11-14
-- Purpose: Store SeleneChat conversation history for ADHD memory support

CREATE TABLE IF NOT EXISTS chat_sessions (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    message_count INTEGER NOT NULL,
    is_pinned INTEGER DEFAULT 0,
    compression_state TEXT DEFAULT 'full',
    compressed_at TEXT,
    full_messages_json TEXT,
    summary_text TEXT
);

CREATE INDEX idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
CREATE INDEX idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);
