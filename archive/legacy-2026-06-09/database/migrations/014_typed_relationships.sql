-- Typed relationships between notes (library science model)
-- BT = Broader Term, NT = Narrower Term, RT = Related Term

CREATE TABLE IF NOT EXISTS note_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    note_a_id INTEGER NOT NULL,
    note_b_id INTEGER NOT NULL,
    relationship_type TEXT NOT NULL CHECK(relationship_type IN
        ('BT', 'NT', 'RT', 'TEMPORAL', 'SAME_THREAD', 'SAME_PROJECT')),
    strength REAL,  -- 0.0 to 1.0, NULL for structural types
    source TEXT NOT NULL CHECK(source IN
        ('llm_extracted', 'embedding_high', 'temporal', 'structural', 'user_explicit')),
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (note_a_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    FOREIGN KEY (note_b_id) REFERENCES raw_notes(id) ON DELETE CASCADE,
    UNIQUE(note_a_id, note_b_id, relationship_type)
);

CREATE INDEX IF NOT EXISTS idx_relationships_a ON note_relationships(note_a_id);
CREATE INDEX IF NOT EXISTS idx_relationships_b ON note_relationships(note_b_id);
CREATE INDEX IF NOT EXISTS idx_relationships_type ON note_relationships(relationship_type);
CREATE INDEX IF NOT EXISTS idx_relationships_source ON note_relationships(source);

-- Concept hierarchy for BT/NT derivation
CREATE TABLE IF NOT EXISTS concept_hierarchy (
    concept TEXT PRIMARY KEY,
    parent_concept TEXT,
    level INTEGER DEFAULT 0,  -- 0 = root, higher = more specific
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_concept_parent ON concept_hierarchy(parent_concept);

-- Note facets for filtering (populated by enhanced LLM extraction)
CREATE TABLE IF NOT EXISTS note_facets (
    raw_note_id INTEGER PRIMARY KEY,
    note_type TEXT CHECK(note_type IN ('task', 'reflection', 'reference', 'idea', 'log')),
    actionability TEXT CHECK(actionability IN ('actionable', 'someday', 'reference', 'done')),
    time_horizon TEXT CHECK(time_horizon IN ('immediate', 'week', 'month', 'timeless')),
    context TEXT,  -- JSON array of contexts
    classified_at TEXT,
    FOREIGN KEY (raw_note_id) REFERENCES raw_notes(id) ON DELETE CASCADE
);
