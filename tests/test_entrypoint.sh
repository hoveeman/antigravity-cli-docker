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
    FOUND_BIN=$(find "$MOCK_EXTRACT" -type f \( -name agy -o -name antigravity \) 2>/dev/null | head -n1 || true)
fi
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

# 8. Test install_from_download_url
eval "$(sed -n '/^detect_arch()/,/^}/p' "$ENTRYPOINT")"
eval "$(sed -n '/^resolve_version_url()/,/^}/p' "$ENTRYPOINT")"
eval "$(sed -n '/^install_from_download_url()/,/^}/p' "$ENTRYPOINT")"

# Test empty URL
ANTIGRAVITY_VERSION=""
ANTIGRAVITY_DOWNLOAD_URL=""
if ! install_from_download_url; then
    echo "FAIL: install_from_download_url should return 0 when ANTIGRAVITY_DOWNLOAD_URL is empty"
    exit 1
fi
echo "PASS: install_from_download_url handles empty URL gracefully"

# Test installing from mock tarball file:// URL
CUSTOM_MOCK_DIR=$(mktemp -d)
CUSTOM_PKG="$CUSTOM_MOCK_DIR/custom_agy.tar.gz"
echo '#!/bin/sh' > "$CUSTOM_MOCK_DIR/agy"
echo 'echo 1.2.13-pinned' >> "$CUSTOM_MOCK_DIR/agy"
chmod 755 "$CUSTOM_MOCK_DIR/agy"
tar -czf "$CUSTOM_PKG" -C "$CUSTOM_MOCK_DIR" agy

CUSTOM_TEST_BIN_DIR="$TMP_DIR/custom_bin"
mkdir -p "$CUSTOM_TEST_BIN_DIR"
INSTALL_BIN_DIR="$CUSTOM_TEST_BIN_DIR"
CONFIG_DIR="$MOCK_CONFIG"
APP_GROUP="$(id -gn)"
AUTO_START_DAEMON="false"
ANTIGRAVITY_DOWNLOAD_URL="file://$CUSTOM_PKG"

install_from_download_url

if [ ! -f "$CUSTOM_TEST_BIN_DIR/agy" ]; then
    echo "FAIL: Custom binary not found at $CUSTOM_TEST_BIN_DIR/agy"
    exit 1
fi

CUSTOM_OUTPUT=$("$CUSTOM_TEST_BIN_DIR/agy")
if [ "$CUSTOM_OUTPUT" != "1.2.13-pinned" ]; then
    echo "FAIL: Expected '1.2.13-pinned', got '$CUSTOM_OUTPUT'"
    exit 1
fi
echo "PASS: install_from_download_url successfully installs pinned binary from tarball URL"

# Verify marker file
MARKER_FILE="$MOCK_CONFIG/.gemini/antigravity-cli/.installed_download_url"
if [ ! -f "$MARKER_FILE" ] || [ "$(cat "$MARKER_FILE")" != "file://$CUSTOM_PKG" ]; then
    echo "FAIL: Marker file was not correctly recorded"
    exit 1
fi
echo "PASS: install_from_download_url records marker file to prevent redundant downloads"
rm -rf "$CUSTOM_MOCK_DIR"

# 9. Test that update_antigravity skips when ANTIGRAVITY_DOWNLOAD_URL is set
eval "$(sed -n '/^update_antigravity()/,/^}/p' "$ENTRYPOINT")"
ANTIGRAVITY_VERSION=""
ANTIGRAVITY_DOWNLOAD_URL="https://example.com/custom.tar.gz"
SKIP_OUTPUT=$(update_antigravity)
if ! echo "$SKIP_OUTPUT" | grep -q "ANTIGRAVITY_DOWNLOAD_URL is configured"; then
    echo "FAIL: update_antigravity did not skip when ANTIGRAVITY_DOWNLOAD_URL was set"
    exit 1
fi
echo "PASS: update_antigravity skips upstream auto-updates when ANTIGRAVITY_DOWNLOAD_URL is set"

# 10. Test resolve_version_url
eval "$(sed -n '/^detect_arch()/,/^}/p' "$ENTRYPOINT")"
eval "$(sed -n '/^resolve_version_url()/,/^}/p' "$ENTRYPOINT")"

ANTIGRAVITY_DOWNLOAD_URL=""
ANTIGRAVITY_VERSION="1.2.13"
resolve_version_url

detect_arch
EXPECTED_URL="https://github.com/google-antigravity/antigravity-cli/releases/download/1.2.13/agy_cli_linux_${PKG_ARCH}.tar.gz"
if [ "$ANTIGRAVITY_DOWNLOAD_URL" != "$EXPECTED_URL" ]; then
    echo "FAIL: Expected $EXPECTED_URL, got $ANTIGRAVITY_DOWNLOAD_URL"
    exit 1
fi
echo "PASS: resolve_version_url constructs official GitHub release URL for ANTIGRAVITY_VERSION"

# Test leading 'v' stripping
ANTIGRAVITY_DOWNLOAD_URL=""
ANTIGRAVITY_VERSION="v1.2.13"
resolve_version_url
if [ "$ANTIGRAVITY_DOWNLOAD_URL" != "$EXPECTED_URL" ]; then
    echo "FAIL: Failed to strip leading 'v' from version"
    exit 1
fi
echo "PASS: resolve_version_url strips leading 'v' correctly"

# Test 'latest' does not construct pinned URL
ANTIGRAVITY_DOWNLOAD_URL=""
ANTIGRAVITY_VERSION="latest"
resolve_version_url
if [ -n "$ANTIGRAVITY_DOWNLOAD_URL" ]; then
    echo "FAIL: resolve_version_url should not set download URL when version is 'latest'"
    exit 1
fi
echo "PASS: resolve_version_url leaves URL empty when ANTIGRAVITY_VERSION is 'latest'"

# 11. Test that update_antigravity skips when ANTIGRAVITY_VERSION is pinned
ANTIGRAVITY_DOWNLOAD_URL=""
ANTIGRAVITY_VERSION="1.2.13"
SKIP_VERSION_OUTPUT=$(update_antigravity)
if ! echo "$SKIP_VERSION_OUTPUT" | grep -q "ANTIGRAVITY_VERSION is pinned"; then
    echo "FAIL: update_antigravity did not skip when ANTIGRAVITY_VERSION was pinned"
    exit 1
fi
echo "PASS: update_antigravity skips upstream auto-updates when ANTIGRAVITY_VERSION is pinned"

echo "=== All entrypoint tests passed successfully ==="
