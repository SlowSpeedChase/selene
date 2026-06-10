-- 020_tiered_context_compression.sql
-- Add essence and fidelity tier columns for tiered context compression
-- Essence: 1-2 sentence LLM distillation of note meaning
-- Fidelity tier: controls what representation is sent to LLM prompts

ALTER TABLE processed_notes ADD COLUMN essence TEXT;
ALTER TABLE processed_notes ADD COLUMN essence_at TEXT;
ALTER TABLE processed_notes ADD COLUMN fidelity_tier TEXT DEFAULT 'full';
ALTER TABLE processed_notes ADD COLUMN fidelity_evaluated_at TEXT;

ALTER TABLE threads ADD COLUMN thread_digest TEXT;
