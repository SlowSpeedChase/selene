#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEST_DB="$PROJECT_DIR/data-test/selene-test.db"
SCHEMA_FILE="$PROJECT_DIR/database/schema.sql"

echo "=== Seeding test database ==="

# Check schema exists
if [ ! -f "$SCHEMA_FILE" ]; then
  echo "ERROR: Schema file not found at $SCHEMA_FILE"
  exit 1
fi

# Remove existing test database
if [ -f "$TEST_DB" ]; then
  echo "Removing existing test database..."
  rm "$TEST_DB"
fi

# Create database with schema
echo "Creating database with schema..."
sqlite3 "$TEST_DB" < "$SCHEMA_FILE"

# Insert synthetic notes
echo "Inserting 18 synthetic notes..."
sqlite3 "$TEST_DB" << 'SEED_SQL'
-- Note 1: Actionable
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Dentist and groceries',
  'Need to call the dentist tomorrow to reschedule my cleaning appointment. Also running low on coffee and oat milk - should grab those this weekend.',
  'testhash001',
  'drafts',
  27,
  147,
  '2026-01-04 09:15:00',
  '2026-01-04 09:15:00',
  'pending',
  'pending_apple'
);

-- Note 2: Needs Planning
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Kitchen renovation ideas',
  'Been thinking about redoing the kitchen. The cabinets are outdated and the layout doesn''t work well. Should probably figure out budget first, then maybe talk to a contractor? Not sure where to even start with permits.',
  'testhash002',
  'drafts',
  43,
  224,
  '2026-01-03 14:30:00',
  '2026-01-03 14:30:00',
  'pending',
  'pending_apple'
);

-- Note 3: Archive Only
INSERT INTO raw_notes (title, content, content_hash, source_type, source_uuid, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Good conversation with mom',
  'Had a nice call with mom today. She told me about her garden and the new tomato varieties she''s trying. Reminded me of summers at grandma''s house.',
  'testhash003',
  'drafts',
  'uuid-note-003',
  30,
  148,
  '2026-01-02 19:45:00',
  '2026-01-02 19:45:00',
  'pending',
  'pending_apple'
);

-- Note 4: Edge Case - Mixed
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Project reflection and next steps',
  'The website redesign went well overall. Learned a lot about CSS grid. Maybe I should write up what worked and what didn''t. Could be useful for the next project.',
  'testhash004',
  'drafts',
  34,
  167,
  '2026-01-01 11:00:00',
  '2026-01-01 11:00:00',
  'pending',
  'pending_apple'
);

-- Note 5: Positive / High Energy
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Finally figured it out',
  'YES! After three days of debugging, I finally found the issue - it was a race condition in the async handler. That feeling when the tests go green is unmatched. Feeling pumped to tackle the next feature.',
  'testhash005',
  'drafts',
  40,
  204,
  '2026-01-04 16:20:00',
  '2026-01-04 16:20:00',
  'pending',
  'pending_apple'
);

-- Note 6: Negative / Stressed
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Overwhelmed today',
  'Too many things competing for attention. The deadline moved up, inbox is overflowing, and I keep forgetting things. Feel like I''m dropping balls everywhere. Need to step back and prioritize but there''s no time to even do that.',
  'testhash006',
  'drafts',
  44,
  230,
  '2026-01-03 18:45:00',
  '2026-01-03 18:45:00',
  'pending',
  'pending_apple'
);

-- Note 7: Neutral / Contemplative
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Observations on routine',
  'Noticed I''m more productive in the morning before checking email. Afternoons tend to fragment. Not sure if this is a pattern worth optimizing for or just how some days go.',
  'testhash007',
  'drafts',
  33,
  175,
  '2026-01-02 21:00:00',
  '2026-01-02 21:00:00',
  'pending',
  'pending_apple'
);

-- Note 8: Mixed / Processing
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Difficult feedback',
  'Got some critical feedback on my proposal today. Initial reaction was defensive but sitting with it now, some points are valid. Still stings a bit. Need to separate the useful critique from the delivery.',
  'testhash008',
  'drafts',
  38,
  202,
  '2026-01-01 20:30:00',
  '2026-01-01 20:30:00',
  'pending',
  'pending_apple'
);

-- Note 9: Theme - Sleep (instance 1)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Tired again',
  'Woke up groggy despite 7 hours. Maybe it''s the late screen time. Should try the no-phone-after-9pm rule again.',
  'testhash009',
  'drafts',
  21,
  110,
  '2026-01-04 07:30:00',
  '2026-01-04 07:30:00',
  'pending',
  'pending_apple'
);

-- Note 10: Theme - Sleep (instance 2)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Sleep experiment',
  'Third night of no screens after 9. Sleep quality does seem better. Waking up feels less like climbing out of a hole.',
  'testhash010',
  'drafts',
  23,
  117,
  '2026-01-02 08:15:00',
  '2026-01-02 08:15:00',
  'pending',
  'pending_apple'
);

-- Note 11: Theme - Sleep (instance 3)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Morning energy',
  'Actually felt rested today. The consistent bedtime is helping. Energy held through the afternoon slump for once.',
  'testhash011',
  'drafts',
  18,
  107,
  '2025-12-30 09:00:00',
  '2025-12-30 09:00:00',
  'pending',
  'pending_apple'
);

-- Note 12: Theme - Work Boundaries
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Working late again',
  'Said I''d stop at 6 but it''s now 9pm. This keeps happening when there''s no clear stopping point. Need some kind of forcing function.',
  'testhash012',
  'drafts',
  27,
  133,
  '2026-01-03 21:15:00',
  '2026-01-03 21:15:00',
  'pending',
  'pending_apple'
);

-- Note 13: Concepts - Productivity + Tools
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Trying new task app',
  'Downloaded Things 3 to replace Reminders. The quick-entry feature is great for capturing tasks without context switching. Wondering if it''ll stick this time or end up abandoned like the others.',
  'testhash013',
  'drafts',
  34,
  192,
  '2026-01-04 12:00:00',
  '2026-01-04 12:00:00',
  'pending',
  'pending_apple'
);

-- Note 14: Concepts - Productivity + ADHD
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Why systems fail',
  'Realized my productivity systems fail when they require too much maintenance. The system needs to be lower friction than the problem it solves. ADHD brain won''t tolerate overhead.',
  'testhash014',
  'drafts',
  32,
  181,
  '2026-01-02 15:30:00',
  '2026-01-02 15:30:00',
  'pending',
  'pending_apple'
);

-- Note 15: Concepts - Tools + Learning
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'n8n learning curve',
  'Finally getting comfortable with n8n. The visual workflow builder clicks with how I think. Function nodes are powerful but easy to overcomplicate.',
  'testhash015',
  'drafts',
  25,
  145,
  '2026-01-01 14:00:00',
  '2026-01-01 14:00:00',
  'pending',
  'pending_apple'
);

-- Note 16: Feedback Note (has #selene-feedback tag)
INSERT INTO raw_notes (title, content, content_hash, source_type, tags, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Selene feedback',
  'The daily summary is helpful but arrives too late. Would be better at 7am instead of midnight. Also wish I could see which notes contributed to detected patterns. #selene-feedback',
  'testhash016',
  'drafts',
  '["selene-feedback"]',
  33,
  178,
  '2026-01-04 08:00:00',
  '2026-01-04 08:00:00',
  'pending',
  'pending_apple'
);

-- Note 17: Duplicate Test (same content as Note 1)
INSERT INTO raw_notes (title, content, content_hash, source_type, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Dentist and groceries',
  'Need to call the dentist tomorrow to reschedule my cleaning appointment. Also running low on coffee and oat milk - should grab those this weekend.',
  'testhash001-dup',
  'drafts',
  27,
  147,
  '2026-01-04 09:15:00',
  '2026-01-04 09:16:00',
  'pending',
  'pending_apple'
);

-- Note 18: Edit Test (same UUID as Note 3, different content)
INSERT INTO raw_notes (title, content, content_hash, source_type, source_uuid, word_count, character_count, created_at, imported_at, status, status_apple)
VALUES (
  'Good conversation with mom (updated)',
  'Had a nice call with mom today. She told me about her garden and the new tomato varieties she''s trying. Reminded me of summers at grandma''s house. She''s also planning to visit next month - need to prep the guest room.',
  'testhash018',
  'drafts',
  'uuid-note-003-edit',
  43,
  218,
  '2026-01-02 19:45:00',
  '2026-01-02 20:00:00',
  'pending',
  'pending_apple'
);

SEED_SQL

# Verify
COUNT=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM raw_notes;")
echo ""
echo "=== Seed complete ==="
echo "Database: $TEST_DB"
echo "Notes inserted: $COUNT"
