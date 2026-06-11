-- Migration: Add Apple Intelligence Processing Support
-- Created: 2025-10-31
-- Description: Adds table for Apple Intelligence processed notes and updates raw_notes statuses

-- Add new columns to raw_notes for Apple processing tracking
ALTER TABLE raw_notes ADD COLUMN status_apple TEXT DEFAULT 'pending_apple';
ALTER TABLE raw_notes ADD COLUMN processed_at_apple DATETIME;

-- Create processed_notes_apple table (identical schema to processed_notes)
CREATE TABLE processed_notes_apple (
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
    processing_model TEXT DEFAULT 'apple_intelligence', -- Track which Apple model was used
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id)
);

-- Create indexes for Apple processing
CREATE INDEX idx_raw_notes_status_apple ON raw_notes(status_apple);
CREATE INDEX idx_processed_notes_apple_raw_id ON processed_notes_apple(raw_note_id);
CREATE INDEX idx_processed_notes_apple_sentiment ON processed_notes_apple(sentiment_analyzed);

-- Comments for status_apple values:
-- 'pending_apple'     - Note is waiting to be processed by Apple Intelligence
-- 'processing_apple'  - Note is currently being processed by Apple Shortcut
-- 'processed_apple'   - Note has been successfully processed by Apple Intelligence
-- 'error_apple'       - Processing failed, available for retry
