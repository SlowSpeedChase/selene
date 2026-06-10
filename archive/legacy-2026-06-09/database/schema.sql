CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE raw_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    content_hash TEXT UNIQUE NOT NULL,
    source_type TEXT DEFAULT 'drafts',
    source_uuid TEXT DEFAULT NULL, -- UUID from Drafts app for tracking individual drafts
    word_count INTEGER DEFAULT 0,
    character_count INTEGER DEFAULT 0,
    tags TEXT, -- JSON array of tags
    created_at DATETIME NOT NULL,
    imported_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME,
    exported_at DATETIME,
    status TEXT DEFAULT 'pending', -- pending, processed, archived
    exported_to_obsidian INTEGER DEFAULT 0,
    test_run TEXT DEFAULT NULL, -- marker for test notes
    status_apple TEXT DEFAULT 'pending_apple', -- pending_apple, processed_apple
    processed_at_apple DATETIME,
    status_folio TEXT DEFAULT NULL -- 'written' once feedback file has been written to project
);
CREATE TABLE processed_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL,
    concepts TEXT, -- JSON array of extracted concepts
    concept_confidence TEXT, -- JSON object with confidence scores
    primary_theme TEXT,
    secondary_themes TEXT, -- JSON array of secondary themes
    theme_confidence REAL,
    sentiment_analyzed INTEGER DEFAULT 0,
    sentiment_data TEXT, -- JSON object with sentiment analysis
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    sentiment_analyzed_at DATETIME,
    processed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE TABLE sentiment_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    processed_note_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    overall_sentiment TEXT,
    sentiment_score REAL,
    emotional_tone TEXT,
    energy_level TEXT,
    stress_indicators INTEGER DEFAULT 0,
    key_emotions TEXT, -- JSON array
    adhd_markers TEXT, -- JSON object
    analysis_confidence REAL,
    analyzed_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (processed_note_id) REFERENCES processed_notes(id),
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);
CREATE TABLE detected_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pattern_type TEXT NOT NULL, -- theme_trend, concept_cluster, etc.
    pattern_name TEXT NOT NULL,
    description TEXT,
    confidence REAL,
    data_points INTEGER,
    pattern_data TEXT, -- JSON object with pattern details
    time_range_start DATETIME,
    time_range_end DATETIME,
    insights TEXT,
    discovered_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active INTEGER DEFAULT 1
);
CREATE TABLE pattern_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    report_id TEXT UNIQUE NOT NULL,
    generated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    time_range_start DATETIME,
    time_range_end DATETIME,
    total_patterns INTEGER,
    high_confidence_count INTEGER,
    medium_confidence_count INTEGER,
    low_confidence_count INTEGER,
    rising_trends_count INTEGER,
    falling_trends_count INTEGER,
    key_insights TEXT, -- JSON array
    recommendations TEXT, -- JSON array
    report_data TEXT -- JSON object with full report
);
CREATE TABLE network_analysis_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    analysis_id TEXT UNIQUE NOT NULL,
    total_notes INTEGER,
    total_connections INTEGER,
    avg_connection_strength REAL,
    concept_based_count INTEGER,
    theme_based_count INTEGER,
    network_stats TEXT, -- JSON object with detailed stats
    analyzed_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_raw_notes_status ON raw_notes(status);
CREATE INDEX idx_raw_notes_content_hash ON raw_notes(content_hash);
CREATE INDEX idx_raw_notes_created_at ON raw_notes(created_at);
CREATE INDEX idx_raw_notes_exported ON raw_notes(exported_to_obsidian);
CREATE INDEX idx_raw_notes_source_uuid ON raw_notes(source_uuid);
CREATE INDEX idx_raw_notes_test_run ON raw_notes(test_run);
CREATE INDEX idx_raw_notes_status_apple ON raw_notes(status_apple);
CREATE INDEX idx_processed_notes_raw_id ON processed_notes(raw_note_id);
CREATE INDEX idx_processed_notes_sentiment ON processed_notes(sentiment_analyzed);
CREATE INDEX idx_sentiment_history_note_ids ON sentiment_history(processed_note_id, raw_note_id);
CREATE INDEX idx_detected_patterns_active ON detected_patterns(is_active);
CREATE INDEX idx_detected_patterns_type ON detected_patterns(pattern_type);

-- Feedback Pipeline: Product feedback capture and backlog generation
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
CREATE INDEX idx_feedback_theme ON feedback_notes(theme);
CREATE INDEX idx_feedback_status ON feedback_notes(status);
CREATE INDEX idx_feedback_cluster ON feedback_notes(cluster_id);
CREATE INDEX idx_feedback_test_run ON feedback_notes(test_run);

-- Thread System: Semantic embeddings and thought consolidation
-- Migration: 013_thread_system.sql (2026-01-04)

-- Vector embedding for each note (768-dim from nomic-embed-text)
CREATE TABLE note_embeddings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    raw_note_id INTEGER NOT NULL UNIQUE,
    embedding BLOB NOT NULL,  -- JSON array of floats (768 dimensions)
    model_version TEXT NOT NULL,  -- e.g., 'nomic-embed-text'
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);

-- Note-to-note similarity links (cosine similarity above threshold)
CREATE TABLE note_associations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    similarity_score REAL NOT NULL,  -- 0.0 to 1.0
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id),
    CHECK(note_a_id < note_b_id),
    CHECK(similarity_score >= 0.0 AND similarity_score <= 1.0)
);

-- Threads: Emergent clusters of related thinking
CREATE TABLE threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    why TEXT,  -- Underlying motivation/goal
    summary TEXT,
    status TEXT DEFAULT 'active',  -- active, paused, completed, abandoned
    note_count INTEGER DEFAULT 0,
    last_activity_at TEXT,
    emotional_charge REAL,  -- Aggregate sentiment
    momentum_score REAL,  -- Recent activity score
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK(status IN ('active', 'paused', 'completed', 'abandoned'))
);

-- Many-to-many: threads <-> notes
CREATE TABLE thread_notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    raw_note_id INTEGER NOT NULL,
    added_at TEXT DEFAULT CURRENT_TIMESTAMP,
    relevance_score REAL,  -- 0.0 to 1.0
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(thread_id, raw_note_id)
);

-- Thread evolution history
CREATE TABLE thread_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    summary_before TEXT,
    summary_after TEXT,
    trigger_note_id INTEGER,
    change_type TEXT NOT NULL,  -- note_added, merged, split, renamed, summarized, created
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (thread_id) REFERENCES threads(id) ON DELETE CASCADE,
    FOREIGN KEY (trigger_note_id) REFERENCES raw_notes(id) ON DELETE SET NULL,
    CHECK(change_type IN ('note_added', 'merged', 'split', 'renamed', 'summarized', 'created'))
);

-- Thread system indexes
CREATE INDEX idx_embeddings_note ON note_embeddings(raw_note_id);
CREATE INDEX idx_associations_a ON note_associations(note_a_id);
CREATE INDEX idx_associations_b ON note_associations(note_b_id);
CREATE INDEX idx_associations_score ON note_associations(similarity_score DESC);
CREATE INDEX idx_thread_notes_thread ON thread_notes(thread_id);
CREATE INDEX idx_thread_notes_note ON thread_notes(raw_note_id);
CREATE INDEX idx_threads_status ON threads(status);
CREATE INDEX idx_threads_activity ON threads(last_activity_at DESC);
CREATE INDEX idx_threads_momentum ON threads(momentum_score DESC);
CREATE INDEX idx_thread_history_thread ON thread_history(thread_id);
