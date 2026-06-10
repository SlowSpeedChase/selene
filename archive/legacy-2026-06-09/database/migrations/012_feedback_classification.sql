-- Migration: 012_feedback_classification.sql
-- Purpose: Add AI classification tracking columns to feedback_notes table
-- Note: status column already exists from migration 009

-- Add classification columns
ALTER TABLE feedback_notes ADD COLUMN category TEXT;
ALTER TABLE feedback_notes ADD COLUMN backlog_id TEXT;
ALTER TABLE feedback_notes ADD COLUMN classified_at DATETIME;
ALTER TABLE feedback_notes ADD COLUMN ai_confidence REAL;
ALTER TABLE feedback_notes ADD COLUMN ai_reasoning TEXT;

-- Index for finding items by category
CREATE INDEX IF NOT EXISTS idx_feedback_category ON feedback_notes(category);

-- Index for finding items by backlog_id
CREATE INDEX IF NOT EXISTS idx_feedback_backlog_id ON feedback_notes(backlog_id);
