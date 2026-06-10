-- 019_calendar_events.sql
-- Add calendar event context to notes
-- Stores best-matching calendar event as JSON when note is written during/after an event

ALTER TABLE raw_notes ADD COLUMN calendar_event TEXT;
