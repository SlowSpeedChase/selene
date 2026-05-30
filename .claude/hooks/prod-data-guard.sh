#!/bin/bash
# Claude Code PreToolUse(Bash) hook: keep real note CONTENT out of Claude's context.
#
# Policy (see docs/plans/2026-05-29-dev-prod-boundary-hardening-design.md, "Refinement"):
#   Deny any Bash command that references a PROD data surface (the real notes DB dir or the
#   iCloud Obsidian vault) UNLESS it is on the sanctioned allowlist. The allowlist is the
#   *only* sanctioned way to look at prod, and is built so note text never reaches Claude:
#     - scripts/selene-inspect.ts   (read-only: schema / counts / coverage, never content)
#     - sqlite3 ".backup"           (moves bytes to a file; nothing printed to stdout)
#     - deploy-prod.sh / rollback-prod.sh / install-prod.sh  (operations, not data)
#
# Robustness over cleverness: we match by PATH, not by parsing SQL. The substring trap is
# load-bearing — prod is "selene-data/", dev is "selene-data-dev/"; the literal "selene-data/"
# is NOT a substring of "selene-data-dev/", so dev workflows pass untouched.
#
# Override: prefix a command with SELENE_GUARD_OFF=1 to deliberately lift the guard during a
# documented prod-down recovery procedure.
#
# Exit 0 = allow, exit 2 = deny (stderr is surfaced back to Claude).
set -u

input=$(cat)
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)

# No command (or non-Bash payload) → nothing to guard.
[ -z "$cmd" ] && exit 0

# Deliberate operator override.
printf '%s' "$cmd" | grep -qF 'SELENE_GUARD_OFF=1' && exit 0

# Does the command reference a PROD data surface?
prod_surface=0
printf '%s' "$cmd" | grep -qF 'selene-data/' && prod_surface=1                       # real notes DB dir (excludes selene-data-dev/)
printf '%s' "$cmd" | grep -qF 'iCloud~md~obsidian/Documents/Selene' && prod_surface=1 # prod Obsidian vault

[ "$prod_surface" -eq 0 ] && exit 0

# It touches prod. Allow only the sanctioned, content-safe operations.
if printf '%s' "$cmd" | grep -qE 'selene-inspect\.ts|\.backup|deploy-prod\.sh|rollback-prod\.sh|install-prod\.sh'; then
    exit 0
fi

# Otherwise: deny, and tell Claude how to get structural visibility without reading notes.
cat >&2 <<'MSG'
BLOCKED by prod-data-guard: this command references the production note store
(~/selene-data/ or the iCloud Obsidian vault), which holds real, private notes.

To inspect prod WITHOUT pulling note text into context, use the read-only inspector:
  npx ts-node scripts/selene-inspect.ts schema [table]   # columns / types
  npx ts-node scripts/selene-inspect.ts counts           # row counts, processed/unprocessed
  npx ts-node scripts/selene-inspect.ts coverage         # missing category/essence/embedding, clusters

For dev work, target the dev DB instead: ~/selene-data-dev/selene.db
If a real incident requires raw prod access, prefix the command with SELENE_GUARD_OFF=1.
MSG
exit 2
