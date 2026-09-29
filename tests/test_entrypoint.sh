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

# 5. Test update extraction logic for 'antigravity' binary name in tarball
MOCK_UPDATE_DIR=$(mktemp -d)
MOCK_TGZ="$MOCK_UPDATE_DIR/test_pkg.tar.gz"
MOCK_EXTRACT="$MOCK_UPDATE_DIR/extract"
mkdir -p "$MOCK_EXTRACT"
MOCK_BIN_DIR="$MOCK_UPDATE_DIR/bin"
mkdir -p "$MOCK_BIN_DIR"

# Create a mock binary named 'antigravity'
echo '#!/bin/sh' > "$MOCK_UPDATE_DIR/antigravity"
echo 'echo 1.2.3' >> "$MOCK_UPDATE_DIR/antigravity"
chmod 755 "$MOCK_UPDATE_DIR/antigravity"
tar -czf "$MOCK_TGZ" -C "$MOCK_UPDATE_DIR" antigravity

tar -xzf "$MOCK_TGZ" -C "$MOCK_EXTRACT"
FOUND_BIN=$(find "$MOCK_EXTRACT" -type f \( -name agy -o -name antigravity \) -perm /111 2>/dev/null | head -n1 || true)
if [ -z "$FOUND_BIN" ]; then
    echo "FAIL: Could not locate extracted binary named antigravity"
    exit 1
fi
cp "$FOUND_BIN" "$MOCK_BIN_DIR/agy"
chmod 755 "$MOCK_BIN_DIR/agy"
if [ "$("$MOCK_BIN_DIR/agy")" != "1.2.3" ]; then
    echo "FAIL: Mock binary did not execute properly"
    exit 1
fi
echo "PASS: Update extraction logic successfully locates and installs 'antigravity' binary as 'agy'"
rm -rf "$MOCK_UPDATE_DIR"

# 6. Test restart_daemon function
eval "$(sed -n '/^restart_daemon()/,/^}/p' "$ENTRYPOINT")"

DAEMON_PID_FILE="$TMP_DIR/mock_daemon.pid"
AUTO_START_DAEMON="true"

# Test when no daemon is running
if ! restart_daemon; then
    echo "FAIL: restart_daemon failed when no daemon was active"
    exit 1
fi
echo "PASS: restart_daemon handles inactive daemon gracefully"

# Test when mock daemon is running
sleep 300 &
MOCK_PID=$!
echo "$MOCK_PID" > "$DAEMON_PID_FILE"

restart_daemon
sleep 0.2

if kill -0 "$MOCK_PID" 2>/dev/null; then
    echo "FAIL: restart_daemon failed to terminate the running mock daemon"
    kill -9 "$MOCK_PID" 2>/dev/null || true
    exit 1
fi
echo "PASS: restart_daemon terminates running daemon process so supervisor can reload it"
rm -f "$DAEMON_PID_FILE"

# 7. Test AUTO_UPDATE_INTERVAL configuration
INTERVAL_TEST=$(bash -c 'AUTO_UPDATE_INTERVAL=3600; source <(grep "^AUTO_UPDATE_INTERVAL=" entrypoint.sh); echo "$AUTO_UPDATE_INTERVAL"')
if [ "$INTERVAL_TEST" != "3600" ]; then
    echo "FAIL: AUTO_UPDATE_INTERVAL should respect environment override"
    exit 1
fi
echo "PASS: AUTO_UPDATE_INTERVAL respects environment override"

echo "=== All entrypoint tests passed successfully ==="
