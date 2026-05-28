---
name: db-query
description: Run a read-only SQLite query against data/selene.db (or the dev DB). Use for quick data inspection, debugging workflow output, or checking row state during development. Pass the SQL as $ARGUMENTS.
disable-model-invocation: true
---

# DB Query

Execute a read-only SQLite query against the Selene database with column-header output.

## Usage

```
/db-query SELECT * FROM raw_notes LIMIT 5
/db-query SELECT COUNT(*) FROM processed_notes WHERE category = 'work'
/db-query .schema raw_notes
```

## Procedure

1. **Determine target database** based on current environment:
   - Production: `~/selene-data/selene.db`
   - Dev (if `SELENE_ENV=development` or user says "dev"): `~/selene-data-dev/selene.db`
   - Default to production unless explicitly asked for dev.

2. **Run the query** with column headers enabled:
   ```bash
   sqlite3 -header -column ~/selene-data/selene.db "$ARGUMENTS"
   ```
   For `.schema` or other dot-commands, run without quoting:
   ```bash
   sqlite3 -header -column ~/selene-data/selene.db <<'EOF'
   $ARGUMENTS
   EOF
   ```

3. **Safety check**: If `$ARGUMENTS` contains `DROP`, `DELETE`, `UPDATE`, `INSERT`, or `ALTER` (case-insensitive), refuse and explain that this skill is read-only. Suggest using `sqlite3` directly for write operations.

4. **Output**: Print results directly. If more than 50 rows returned, note the count and suggest adding `LIMIT`.

## Common Queries

```sql
-- Recent notes
SELECT id, title, created_at FROM raw_notes ORDER BY created_at DESC LIMIT 10;

-- Processing backlog
SELECT COUNT(*) AS pending FROM raw_notes WHERE processed = 0;

-- Notes by category
SELECT category, COUNT(*) AS count FROM processed_notes GROUP BY category ORDER BY count DESC;

-- Recent essences
SELECT n.title, e.essence FROM note_essences e JOIN raw_notes n ON e.note_id = n.id ORDER BY e.distilled_at DESC LIMIT 5;

-- Check schema
.schema raw_notes
```
