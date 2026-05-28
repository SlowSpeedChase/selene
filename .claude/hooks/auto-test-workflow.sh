#!/usr/bin/env bash
# Auto-run matching .test.ts when a workflow .ts file is edited
FILE=$(echo "$CLAUDE_FILE_PATHS" | grep -oE 'src/workflows/[^[:space:]]+\.ts' | grep -v '\.test\.ts' | head -1)
if [ -n "$FILE" ]; then
  TEST="${FILE%.ts}.test.ts"
  if [ -f "/Users/chaseeasterling/selene/$TEST" ]; then
    echo "[auto-test] Running $TEST"
    cd /Users/chaseeasterling/selene && npx ts-node "$TEST" 2>&1 | tail -20
  fi
fi
