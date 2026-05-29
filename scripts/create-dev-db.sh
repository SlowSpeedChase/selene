#!/bin/bash
#
# create-dev-db.sh - Initialize empty development database with full schema
#
# This script:
# 1. Creates ~/selene-data-dev/ directory structure
# 2. Creates SQLite database with all production tables and indexes
# 3. Marks database with environment = 'development' metadata
#
# Usage: ./scripts/create-dev-db.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DEV_DIR="$HOME/selene-data-dev"
DEV_DB="$DEV_DIR/selene.db"

echo -e "${GREEN}=== Selene Development Database Creator ===${NC}"
echo ""

# Check if database already exists
if [ -f "$DEV_DB" ]; then
  echo -e "${YELLOW}Warning: Development database already exists at $DEV_DB${NC}"
  read -p "Overwrite? (y/n) " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${RED}Aborted.${NC}"
    exit 0
  fi
  rm "$DEV_DB"
  echo -e "${YELLOW}Removed existing database.${NC}"
  echo ""
fi

# Step 1: Create directory structure
echo -e "Step 1: Creating directory structure..."
echo "----------------------------------------"
mkdir -p "$DEV_DIR/vault"
mkdir -p "$DEV_DIR/digests"
mkdir -p "$DEV_DIR/logs"
mkdir -p "$DEV_DIR/voice-memos"
echo -e "  ${GREEN}Created${NC} $DEV_DIR/"
echo -e "  ${GREEN}Created${NC} $DEV_DIR/vault/"
echo -e "  ${GREEN}Created${NC} $DEV_DIR/digests/"
echo -e "  ${GREEN}Created${NC} $DEV_DIR/logs/"
echo -e "  ${GREEN}Created${NC} $DEV_DIR/voice-memos/"
echo ""

# Step 2: Create database with full schema
echo -e "Step 2: Creating database with production schema..."
echo "----------------------------------------"

sqlite3 "$DEV_DB" <<'SQL'
-- Core tables
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    source_type TEXT DEFAULT 'drafts',
    word_count INTEGER DEFAULT 0,
    character_count INTEGER DEFAULT 0,
    tags TEXT,
    created_at DATETIME NOT NULL,
    imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME,
    exported_at DATETIME,
    status TEXT DEFAULT 'pending',
    exported_to_obsidian INTEGER DEFAULT 0,
    test_run TEXT DEFAULT NULL,
    status_apple TEXT DEFAULT 'pending_apple',
    processed_at_apple DATETIME,
    inbox_status TEXT DEFAULT 'pending',
    suggested_type TEXT,
    suggested_project_id INTEGER,
    tasks_extracted BOOLEAN DEFAULT 0,
    tasks_extracted_at TEXT,
    source_uuid TEXT DEFAULT NULL,
    calendar_event TEXT,
    capture_type TEXT DEFAULT 'drafts',
    source_note_id INTEGER REFERENCES raw_notes(id)
);
CREATE INDEX idx_raw_notes_status ON raw_notes(status);
CREATE INDEX idx_raw_notes_content_hash ON raw_notes(content_hash);
CREATE INDEX idx_raw_notes_created_at ON raw_notes(created_at);
CREATE INDEX idx_raw_notes_exported ON raw_notes(exported_to_obsidian);
CREATE INDEX idx_raw_notes_test_run ON raw_notes(test_run);
CREATE INDEX idx_raw_notes_status_apple ON raw_notes(status_apple);
CREATE INDEX idx_raw_notes_inbox_status ON raw_notes(inbox_status);
CREATE INDEX idx_raw_notes_source_uuid ON raw_notes(source_uuid);

CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,
    concept_confidence TEXT,
    primary_theme TEXT,
    secondary_themes TEXT,
    theme_confidence REAL,
    sentiment_analyzed INTEGER DEFAULT 0,
    sentiment_data TEXT,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    sentiment_analyzed_at DATETIME,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    things_integration_status TEXT
        CHECK(things_integration_status IN ('pending', 'tasks_created', 'no_tasks', 'error'))
        DEFAULT 'pending',
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE INDEX idx_processed_notes_raw_id ON processed_notes(raw_note_id);
CREATE INDEX idx_processed_notes_sentiment ON processed_notes(sentiment_analyzed);

CREATE TABLE processed_notes_apple (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT,
    concept_confidence TEXT,
    primary_theme TEXT,
    secondary_themes TEXT,
    theme_confidence REAL,
    sentiment_analyzed INTEGER DEFAULT 0,
    sentiment_data TEXT,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    sentiment_analyzed_at DATETIME,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processing_model TEXT DEFAULT 'apple_intelligence',
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE INDEX idx_processed_notes_apple_raw_id ON processed_notes_apple(raw_note_id);
CREATE INDEX idx_processed_notes_apple_sentiment ON processed_notes_apple(sentiment_analyzed);

CREATE TABLE note_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,
    model_version TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);
CREATE INDEX idx_embeddings_note ON note_embeddings(raw_note_id);

CREATE TABLE note_associations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    similarity_score REAL NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id),
    CHECK(note_a_id < note_b_id),
    CHECK(similarity_score >= 0.0 AND similarity_score <= 1.0)
);
CREATE INDEX idx_associations_a ON note_associations(note_a_id);
CREATE INDEX idx_associations_b ON note_associations(note_b_id);
CREATE INDEX idx_associations_score ON note_associations(similarity_score DESC);

-- Thread system
CREATE TABLE threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    why TEXT,
    summary TEXT,
    status TEXT DEFAULT 'active',
    note_count INTEGER DEFAULT 0,
    last_activity_at TEXT,
    emotional_charge REAL,
    momentum_score REAL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'paused', 'completed', 'abandoned'))
);
CREATE INDEX idx_threads_status ON threads(status);
CREATE INDEX idx_threads_activity ON threads(last_activity_at DESC);
CREATE INDEX idx_threads_momentum ON threads(momentum_score DESC);

CREATE TABLE thread_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    added_at TEXT DEFAULT CURRENT_TIMESTAMP,
    relevance_score REAL,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(thread_id, raw_note_id)
);
CREATE INDEX idx_thread_notes_thread ON thread_notes(thread_id);
CREATE INDEX idx_thread_notes_note ON thread_notes(raw_note_id);

CREATE TABLE thread_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,
    change_type TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (trigger_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL,
    CHECK(change_type IN ('note_added', 'merged', 'split', 'renamed', 'summarized', 'created'))
);
CREATE INDEX idx_thread_history_thread ON thread_history(thread_id);

CREATE TABLE thread_tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    things_task_id TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    completed_at TEXT,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    UNIQUE(thread_id, things_task_id)
);
CREATE INDEX idx_thread_tasks_thread ON thread_tasks(thread_id);
CREATE INDEX idx_thread_tasks_things ON thread_tasks(things_task_id);

-- Chat system
CREATE TABLE chat_sessions (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    message_count INTEGER NOT NULL,
    is_pinned INTEGER NOT NULL DEFAULT 0,
    compression_state TEXT NOT NULL DEFAULT 'full',
    compressed_at TEXT,
    full_messages_json TEXT,
    summary_text TEXT
);
CREATE INDEX idx_chat_sessions_updated_at ON chat_sessions(updated_at DESC);
CREATE INDEX idx_chat_sessions_compression ON chat_sessions(compression_state, created_at);

CREATE TABLE conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_conversations_session ON conversations(session_id);
CREATE INDEX idx_conversations_created ON conversations(created_at);

CREATE TABLE conversation_memories (
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
CREATE INDEX idx_memories_type ON conversation_memories(memory_type);
CREATE INDEX idx_memories_confidence ON conversation_memories(confidence);
CREATE INDEX idx_memories_last_accessed ON conversation_memories(last_accessed);

-- Relationships
CREATE TABLE note_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    relationship_type TEXT NOT NULL CHECK(relationship_type IN
        ('BT', 'NT', 'RT', 'TEMPORAL', 'SAME_THREAD', 'SAME_PROJECT')),
    strength REAL,
    source TEXT NOT NULL CHECK(source IN
        ('llm_extracted', 'embedding_high', 'temporal', 'structural', 'user_explicit')),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id, relationship_type)
);
CREATE INDEX idx_relationships_a ON note_relationships(note_a_id);
CREATE INDEX idx_relationships_b ON note_relationships(note_b_id);
CREATE INDEX idx_relationships_type ON note_relationships(relationship_type);
CREATE INDEX idx_relationships_source ON note_relationships(source);

-- Analytics
CREATE TABLE sentiment_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    processed_note_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    stress_indicators INTEGER DEFAULT 0,
    key_emotions TEXT,
    adhd_markers TEXT,
    analysis_confidence REAL,
    analyzed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (processed_note_id) REFERENCES processed_notes(id),
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE INDEX idx_sentiment_history_note_ids ON sentiment_history(processed_note_id, raw_note_id);

CREATE TABLE detected_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_name TEXT,
    description TEXT,
    pattern_data TEXT,
    insights TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE note_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
    note_id INTEGER NOT NULL,
    chunk_index INTEGER NOT NULL,
    content TEXT NOT NULL,
    topic TEXT,
    token_count INTEGER NOT NULL,
    embedding BLOB,
    created_at TEXT NOT NULL,
    UNIQUE (note_id, chunk_index)
);
CREATE INDEX index_note_chunks_on_note_id ON note_chunks(note_id);

-- Device tokens
CREATE TABLE device_tokens (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    token TEXT NOT NULL UNIQUE,
    platform TEXT NOT NULL DEFAULT 'ios',
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Environment metadata
CREATE TABLE _selene_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO _selene_metadata (key, value) VALUES ('environment', 'development');
INSERT INTO _selene_metadata (key, value) VALUES ('created_at', datetime('now'));
SQL

echo -e "  ${GREEN}Created${NC} database with full production schema"
echo ""

# Step 3: Verify
echo -e "Step 3: Verifying database..."
echo "----------------------------------------"

TABLE_COUNT=$(sqlite3 "$DEV_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';")
INDEX_COUNT=$(sqlite3 "$DEV_DB" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
ENV=$(sqlite3 "$DEV_DB" "SELECT value FROM _selene_metadata WHERE key='environment';")

echo -e "  Tables:      ${GREEN}${TABLE_COUNT}${NC}"
echo -e "  Indexes:     ${GREEN}${INDEX_COUNT}${NC}"
echo -e "  Environment: ${GREEN}${ENV}${NC}"
echo ""

# Summary
echo -e "${GREEN}=== Development Database Ready ===${NC}"
echo ""
echo "  Database: $DEV_DB"
echo "  Vault:    $DEV_DIR/vault/"
echo "  Digests:  $DEV_DIR/digests/"
echo "  Logs:     $DEV_DIR/logs/"
echo "  Voice:    $DEV_DIR/voice-memos/"
echo ""
echo -e "To use: ${YELLOW}export SELENE_DB_PATH=$DEV_DB${NC}"
