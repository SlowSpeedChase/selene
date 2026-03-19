-- Add capture_type column to raw_notes
ALTER TABLE raw_notes ADD COLUMN capture_type TEXT DEFAULT 'drafts';

-- Backfill voice memos (they come in with title starting "Voice Memo" or tag voice-memo)
UPDATE raw_notes SET capture_type = 'voice'
WHERE tags LIKE '%voice-memo%' OR title LIKE 'Voice Memo%';

-- Index for routing queries
CREATE INDEX idx_raw_notes_capture_type ON raw_notes(capture_type);
