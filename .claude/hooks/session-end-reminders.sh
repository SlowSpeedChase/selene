#!/bin/bash
# Fired by the Stop hook. Detects whether workflow or launchd files changed
# and adds backend-block-diagrams.md to the reminder when they did.

changed=$(git status --porcelain 2>/dev/null | cut -c4- | grep -E 'src/workflows/|launchd/')

if [ -n "$changed" ]; then
  echo '{"systemMessage": "Session end: Workflow or launchd files changed this session. Update docs/backend-block-diagrams.md to reflect current system. Also update docs/USER-EXPERIENCE.md if any user-facing features changed."}'
else
  echo '{"systemMessage": "Session end: Update docs/USER-EXPERIENCE.md if any workflows, features, or status changed this session."}'
fi
