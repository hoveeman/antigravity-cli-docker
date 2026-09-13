#!/usr/bin/env bash
set -euo pipefail

echo "=== Running entrypoint test suite ==="

ENTRYPOINT="./entrypoint.sh"

if [ ! -f "$ENTRYPOINT" ]; then
    echo "FAIL: $ENTRYPOINT not found"
    exit 1
fi

# 1. Test bash syntax check
bash -n "$ENTRYPOINT"
echo "PASS: entrypoint.sh has valid bash syntax"

# 2. Test executable bit
if [ ! -x "$ENTRYPOINT" ]; then
    echo "FAIL: $ENTRYPOINT is not executable"
    exit 1
fi
echo "PASS: entrypoint.sh is executable"

# 3. Test dry-run execution or function definitions
# Create a temporary mock directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

export MOCK_CONFIG="$TMP_DIR/config"
export MOCK_WORKSPACES="$TMP_DIR/workspaces"
mkdir -p "$MOCK_CONFIG" "$MOCK_WORKSPACES"

# Test dry run mode via environment variable
TEST_DRY_RUN=1 bash "$ENTRYPOINT" --dry-run-test

echo "=== All entrypoint tests passed successfully ==="
