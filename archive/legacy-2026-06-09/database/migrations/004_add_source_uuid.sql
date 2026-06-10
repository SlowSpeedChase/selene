-- Migration 004: Add source_uuid column to raw_notes table
-- Created: 2025-11-01
-- Purpose: Enable draft UUID tracking for edit detection and version management

-- Add source_uuid column to raw_notes
-- NULL is allowed for backward compatibility (non-Drafts sources)
ALTER TABLE raw_notes ADD COLUMN source_uuid TEXT DEFAULT NULL;

-- Create index for fast UUID lookups
CREATE INDEX IF NOT EXISTS idx_raw_notes_source_uuid ON raw_notes(source_uuid);

-- Verify the migration
SELECT
    'Migration 004 complete' as status,
    COUNT(*) as total_notes,
    COUNT(source_uuid) as notes_with_uuid
FROM raw_notes;
