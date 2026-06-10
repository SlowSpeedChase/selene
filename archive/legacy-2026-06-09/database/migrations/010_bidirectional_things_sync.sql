-- 010_bidirectional_things_sync.sql
-- Phase 7.2e: Add columns for bidirectional Things sync
--
-- Adds status tracking columns to task_links for syncing
-- task completion status from Things 3 back to Selene.

-- Add Things status column (open, completed, canceled)
ALTER TABLE task_links ADD COLUMN things_status TEXT DEFAULT 'open';

-- Add completion timestamp from Things
ALTER TABLE task_links ADD COLUMN things_completed_at TEXT;

-- Add last sync timestamp
ALTER TABLE task_links ADD COLUMN last_synced_at TEXT;

-- Add updated_at for tracking changes
ALTER TABLE task_links ADD COLUMN updated_at TEXT DEFAULT CURRENT_TIMESTAMP;

-- Index for finding tasks needing sync (open tasks)
CREATE INDEX IF NOT EXISTS idx_task_links_status ON task_links(things_status);

-- Index for finding recently synced
CREATE INDEX IF NOT EXISTS idx_task_links_synced ON task_links(last_synced_at);
