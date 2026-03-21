#!/bin/bash
#
# create-synthetic-test-db.sh - Create synthetic test database (no production data needed)
#
# Use this when you don't have access to the production database.
# Creates a test database with realistic fake data for development.
#
# Usage: ./scripts/create-synthetic-test-db.sh
#

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

TEST_DIR="$PROJECT_ROOT/data-test"
TEST_DB="$TEST_DIR/selene.db"

echo -e "${GREEN}=== Selene Synthetic Test Database Creator ===${NC}"
echo ""
echo "This creates a test database with fake data (no production data needed)."
echo ""

# Create directories
mkdir -p "$TEST_DIR"
mkdir -p "$TEST_DIR/vault"
mkdir -p "$TEST_DIR/digests"

# Remove old test database
if [ -f "$TEST_DB" ]; then
  echo "Removing old test database..."
  rm -f "$TEST_DB" "$TEST_DB-journal" "$TEST_DB-wal" "$TEST_DB-shm"
fi

echo -e "${GREEN}Creating synthetic test database...${NC}"

# Create database with schema
sqlite3 "$TEST_DB" <<'SQL'
-- Metadata table
CREATE TABLE IF NOT EXISTS _selene_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO _selene_metadata (key, value) VALUES ('environment', 'test');
INSERT INTO _selene_metadata (key, value) VALUES ('created_at', datetime('now'));
INSERT INTO _selene_metadata (key, value) VALUES ('source', 'synthetic');

-- Raw notes table
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    source_type TEXT DEFAULT 'drafts',
    source_uuid TEXT DEFAULT NULL,
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
    processed_at_apple DATETIME
);

-- Processed notes table
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
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);

-- Note embeddings table
CREATE TABLE note_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,
    model_version TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);

-- Note associations table
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
    CHECK(note_a_id < note_b_id)
);

-- Threads table
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
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Thread notes table
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

-- Thread history table
CREATE TABLE thread_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,
    change_type TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE
);

-- Chat sessions table
CREATE TABLE chat_sessions (
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

-- Conversations table
CREATE TABLE conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('user', 'assistant')),
    content TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Conversation memories table
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

-- Detected patterns table
CREATE TABLE detected_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_type TEXT NOT NULL,
    pattern_name TEXT NOT NULL,
    description TEXT,
    confidence REAL,
    data_points INTEGER,
    pattern_data TEXT,
    time_range_start DATETIME,
    time_range_end DATETIME,
    insights TEXT,
    discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active INTEGER DEFAULT 1
);

-- Feedback notes table
CREATE TABLE feedback_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME,
    user_story TEXT,
    theme TEXT,
    cluster_id INTEGER,
    priority INTEGER DEFAULT 1,
    mention_count INTEGER DEFAULT 1,
    status TEXT DEFAULT 'open',
    implemented_pr TEXT,
    implemented_at DATETIME,
    test_run TEXT DEFAULT NULL,
    processing_error TEXT
);

-- Create indexes
CREATE INDEX idx_raw_notes_status ON raw_notes(status);
CREATE INDEX idx_raw_notes_content_hash ON raw_notes(content_hash);
CREATE INDEX idx_raw_notes_created_at ON raw_notes(created_at);
CREATE INDEX idx_processed_notes_raw_id ON processed_notes(raw_note_id);
CREATE INDEX idx_embeddings_note ON note_embeddings(raw_note_id);
CREATE INDEX idx_associations_a ON note_associations(note_a_id);
CREATE INDEX idx_associations_b ON note_associations(note_b_id);
CREATE INDEX idx_threads_status ON threads(status);
CREATE INDEX idx_thread_notes_thread ON thread_notes(thread_id);
CREATE INDEX idx_thread_notes_note ON thread_notes(raw_note_id);

-- Insert synthetic notes
INSERT INTO raw_notes (title, content, content_hash, word_count, character_count, tags, created_at, status)
VALUES
('Note 00001', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.', 'hash001', 19, 123, '["tag_1", "tag_2"]', datetime('now', '-7 days'), 'processed'),
('Note 00002', 'Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.', 'hash002', 17, 108, '["tag_2", "tag_3"]', datetime('now', '-6 days'), 'processed'),
('Note 00003', 'Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur.', 'hash003', 16, 102, '["tag_1"]', datetime('now', '-5 days'), 'processed'),
('Note 00004', 'Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.', 'hash004', 17, 110, '["tag_3", "tag_4"]', datetime('now', '-4 days'), 'processed'),
('Note 00005', 'Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium.', 'hash005', 14, 97, '["tag_2"]', datetime('now', '-3 days'), 'processed'),
('Note 00006', 'Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit.', 'hash006', 12, 75, '["tag_1", "tag_4"]', datetime('now', '-2 days'), 'processed'),
('Note 00007', 'Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit.', 'hash007', 14, 93, '["tag_5"]', datetime('now', '-1 days'), 'processed'),
('Note 00008', 'Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur.', 'hash008', 17, 102, '["tag_2", "tag_5"]', datetime('now'), 'pending'),
('Note 00009', 'At vero eos et accusamus et iusto odio dignissimos ducimus qui blanditiis praesentium voluptatum.', 'hash009', 15, 98, '["tag_3"]', datetime('now'), 'pending'),
('Note 00010', 'Et harum quidem rerum facilis est et expedita distinctio. Nam libero tempore, cum soluta nobis.', 'hash010', 16, 95, '["tag_1", "tag_2", "tag_3"]', datetime('now'), 'pending');

-- Insert processed notes for processed raw notes
INSERT INTO processed_notes (raw_note_id, concepts, primary_theme, secondary_themes, overall_sentiment, sentiment_score, energy_level, processed_at)
VALUES
(1, '["concept_1", "concept_2"]', 'theme_1', '["theme_2"]', 'positive', 0.7, 'medium', datetime('now', '-7 days')),
(2, '["concept_2", "concept_3"]', 'theme_2', '["theme_1"]', 'neutral', 0.5, 'medium', datetime('now', '-6 days')),
(3, '["concept_1"]', 'theme_1', '[]', 'positive', 0.8, 'high', datetime('now', '-5 days')),
(4, '["concept_3", "concept_4"]', 'theme_3', '["theme_2"]', 'negative', 0.3, 'low', datetime('now', '-4 days')),
(5, '["concept_2"]', 'theme_2', '[]', 'neutral', 0.5, 'medium', datetime('now', '-3 days')),
(6, '["concept_1", "concept_4"]', 'theme_1', '["theme_3"]', 'positive', 0.6, 'medium', datetime('now', '-2 days')),
(7, '["concept_5"]', 'theme_4', '[]', 'neutral', 0.5, 'medium', datetime('now', '-1 days'));

-- Insert threads
INSERT INTO threads (name, why, summary, status, note_count, last_activity_at, momentum_score)
VALUES
('Thread 001', 'Exploring concept_1 and related ideas', 'This thread contains notes about concept_1 and theme_1.', 'active', 3, datetime('now', '-2 days'), 0.7),
('Thread 002', 'Understanding concept_2 patterns', 'This thread explores concept_2 across multiple notes.', 'active', 2, datetime('now', '-3 days'), 0.5);

-- Link notes to threads
INSERT INTO thread_notes (thread_id, raw_note_id, relevance_score)
VALUES
(1, 1, 0.9),
(1, 3, 0.8),
(1, 6, 0.7),
(2, 2, 0.85),
(2, 5, 0.75);

-- Insert some associations
INSERT INTO note_associations (note_a_id, note_b_id, similarity_score)
VALUES
(1, 3, 0.85),
(1, 6, 0.72),
(2, 5, 0.78),
(3, 6, 0.65),
(4, 7, 0.55);

SQL

echo ""
echo -e "${GREEN}=== Synthetic Test Database Created ===${NC}"
echo ""
echo "Statistics:"
sqlite3 "$TEST_DB" <<'SQL'
SELECT 'raw_notes: ' || COUNT(*) FROM raw_notes;
SELECT 'processed_notes: ' || COUNT(*) FROM processed_notes;
SELECT 'threads: ' || COUNT(*) FROM threads;
SELECT 'note_associations: ' || COUNT(*) FROM note_associations;
SQL

echo ""
echo -e "${GREEN}Test database created at: $TEST_DB${NC}"
echo ""
echo "To use the test environment:"
echo "  npx ts-node src/workflows/process-llm.ts"
echo ""
echo "The .env.development file sets SELENE_ENV=test automatically."
