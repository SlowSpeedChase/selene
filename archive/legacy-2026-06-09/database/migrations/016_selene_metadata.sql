-- Migration: 016_selene_metadata.sql
-- Purpose: Add metadata table for environment identification
-- Date: 2026-02-06

-- Metadata table for environment identification and configuration
CREATE TABLE IF NOT EXISTS _selene_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP
);

-- Production databases won't have this row
-- Test databases will have environment = 'test'
-- This allows fail-safe verification in test mode
