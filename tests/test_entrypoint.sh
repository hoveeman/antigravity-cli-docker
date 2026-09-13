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

# 4. Test authentication detection function
eval "$(sed -n '/^is_authenticated()/,/^}/p' "$ENTRYPOINT")"

CONFIG_DIR="$MOCK_CONFIG"
if is_authenticated; then
    echo "FAIL: is_authenticated should return false when no credentials exist"
    exit 1
fi
echo "PASS: is_authenticated returns false when credentials do not exist"

# Test with token file present
mkdir -p "$MOCK_CONFIG/.gemini/antigravity-cli"
touch "$MOCK_CONFIG/.gemini/antigravity-cli/antigravity-oauth-token"
if ! is_authenticated; then
    echo "FAIL: is_authenticated should return true when antigravity-oauth-token exists"
    exit 1
fi
echo "PASS: is_authenticated returns true when antigravity-oauth-token exists"
rm -f "$MOCK_CONFIG/.gemini/antigravity-cli/antigravity-oauth-token"

# Test with GEMINI_API_KEY set
GEMINI_API_KEY="test_key"
if ! is_authenticated; then
    echo "FAIL: is_authenticated should return true when GEMINI_API_KEY is set"
    exit 1
fi
echo "PASS: is_authenticated returns true when GEMINI_API_KEY is set"
unset GEMINI_API_KEY

echo "=== All entrypoint tests passed successfully ==="
