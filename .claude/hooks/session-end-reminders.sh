#!/bin/bash
# Fired by the Stop hook. Detects whether workflow or launchd files changed
# and, when they did, checks the generated system map for drift and reminds
# about the block diagrams.

changed=$(git status --porcelain 2>/dev/null | cut -c4- | grep -E 'src/workflows/|launchd/')

if [ -n "$changed" ]; then
  # The live inventory (docs/SYSTEM-MAP.md) is generated from workflows + plists.
  # If it no longer matches the code, surface that loudly — drift is the whole
  # thing this map exists to prevent.
  drift=""
  if [ -f scripts/gen-system-map.ts ] && ! npx ts-node scripts/gen-system-map.ts --check >/dev/null 2>&1; then
    drift=" docs/SYSTEM-MAP.md is OUT OF DATE — run: npx ts-node scripts/gen-system-map.ts."
  fi
  echo "{\"systemMessage\": \"Session end: Workflow or launchd files changed this session.${drift} Update docs/backend-block-diagrams.md to reflect the current system. Also update docs/USER-EXPERIENCE.md if any user-facing features changed.\"}"
else
  echo '{"systemMessage": "Session end: Update docs/USER-EXPERIENCE.md if any workflows, features, or status changed this session."}'
fi
