#!/bin/bash
# test-get-status.sh
# Test script for get-task-status.scpt
#
# Usage: ./test-get-status.sh [task_id]
#
# If no task_id provided, tests error handling only.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Testing get-task-status.scpt ==="
echo ""

# Test 1: Missing argument
echo "Test 1: Missing argument (should return error)"
RESULT=$("$SCRIPT_DIR/check-task-status.sh" 2>&1 || true)
if echo "$RESULT" | grep -q '"error"'; then
    echo "  PASS: Got expected error response"
else
    echo "  FAIL: Expected error response"
fi
echo "  Response: $RESULT"
echo ""

# Test 2: Empty argument
echo "Test 2: Empty argument (should return error)"
RESULT=$("$SCRIPT_DIR/check-task-status.sh" "" 2>&1 || true)
if echo "$RESULT" | grep -q '"error"'; then
    echo "  PASS: Got expected error response"
else
    echo "  FAIL: Expected error response"
fi
echo "  Response: $RESULT"
echo ""

# Test 3: Invalid task ID
echo "Test 3: Invalid task ID (should return 'not found')"
RESULT=$("$SCRIPT_DIR/check-task-status.sh" "invalid-task-id-12345" 2>&1 || true)
if echo "$RESULT" | grep -q '"error"'; then
    echo "  PASS: Got expected error response"
else
    echo "  FAIL: Expected error response"
fi
echo "  Response: $RESULT"
echo ""

# Test 4: Real task ID (if provided)
if [ -n "${1:-}" ]; then
    echo "Test 4: Real task ID: $1"
    RESULT=$("$SCRIPT_DIR/check-task-status.sh" "$1" 2>&1)
    echo "  Response: $RESULT"

    if echo "$RESULT" | grep -q '"status"'; then
        echo "  PASS: Got valid status response"
    else
        echo "  INFO: Response may indicate task not found"
    fi
else
    echo "Test 4: Skipped (no task ID provided)"
    echo "  To test with a real task, run: $0 <things_task_id>"
fi

echo ""
echo "=== Tests Complete ==="
