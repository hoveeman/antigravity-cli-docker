#!/usr/bin/env bash
set -eo pipefail

# ==============================================================================
# Google Antigravity CLI Container Entrypoint for Unraid & Docker
# ==============================================================================

# Environment variable defaults
PUID=${PUID:-99}
PGID=${PGID:-100}
UMASK=${UMASK:-002}
CONFIG_DIR=${MOCK_CONFIG:-/config}
WORKSPACES_DIR=${MOCK_WORKSPACES:-/workspaces}
ANTIGRAVITY_INSTANCE_NAME=${ANTIGRAVITY_INSTANCE_NAME:-unraid-server}
AUTO_START_DAEMON=${AUTO_START_DAEMON:-true}
AUTO_UPDATE=${AUTO_UPDATE:-true}

umask "$UMASK"

echo "=================================================================="
echo " Starting Antigravity CLI Container"
echo " Instance Name: $ANTIGRAVITY_INSTANCE_NAME"
echo " PUID: $PUID | PGID: $PGID"
echo " Config Dir: $CONFIG_DIR"
echo " Workspaces Dir: $WORKSPACES_DIR"
echo "=================================================================="

# Dry run mode check for testing
if [ "${1:-}" = "--dry-run-test" ] || [ "${TEST_DRY_RUN:-0}" = "1" ]; then
    echo "Dry run test completed successfully."
    exit 0
fi

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$WORKSPACES_DIR" "$CONFIG_DIR/.local/bin" "$CONFIG_DIR/.gemini"

# Set up user and group matching PUID/PGID if running as root
APP_USER="antigravity"
APP_GROUP="antigravity"

if [ "$(id -u)" = "0" ]; then
    # Group setup
    EXISTING_GROUP=$(getent group "$PGID" | cut -d: -f1 || true)
    if [ -n "$EXISTING_GROUP" ]; then
        APP_GROUP="$EXISTING_GROUP"
    else
        groupadd -r -g "$PGID" "$APP_GROUP" || true
    fi

    # User setup
    EXISTING_USER=$(getent passwd "$PUID" | cut -d: -f1 || true)
    if [ -n "$EXISTING_USER" ]; then
        APP_USER="$EXISTING_USER"
        usermod -d "$CONFIG_DIR" -g "$APP_GROUP" "$APP_USER" 2>/dev/null || true
    else
        useradd -r -u "$PUID" -g "$APP_GROUP" -d "$CONFIG_DIR" -s /bin/bash "$APP_USER" || true
    fi

    # Sudoers configuration for seamless developer workflow
    echo "$APP_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/antigravity
    chmod 0440 /etc/sudoers.d/antigravity

    # Fix ownership of config directory and binary path
    chown -R "$PUID:$PGID" "$CONFIG_DIR" || true
    chmod -R u+rwX,go+rX "$CONFIG_DIR" || true
    chgrp -R "$APP_GROUP" /usr/local/bin || true
    chmod 775 /usr/local/bin || true
fi

# Export environment paths
export HOME="$CONFIG_DIR"
export PATH="$CONFIG_DIR/.local/bin:/usr/local/bin:$PATH"

# Function to check and update Antigravity CLI
update_antigravity() {
    if [ "$AUTO_UPDATE" != "true" ]; then
        return 0
    fi

    echo "=== Checking for Google Antigravity CLI updates ==="
    
    # Detect system architecture
    ARCH="amd64"
    case "$(uname -m)" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) echo "Warning: Unknown architecture $(uname -m), skipping update check." ; return 0 ;;
    esac

    MANIFEST_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_${ARCH}.json"
    
    # Check remote version with timeout
    REMOTE_JSON=$(curl -fsSL --connect-timeout 5 --max-time 15 "$MANIFEST_URL" 2>/dev/null || true)
    if [ -n "$REMOTE_JSON" ]; then
        REMOTE_VERSION=$(echo "$REMOTE_JSON" | grep -o '"version": *"[^"]*"' | cut -d'"' -f4 || true)
        REMOTE_URL=$(echo "$REMOTE_JSON" | grep -o '"url": *"[^"]*"' | cut -d'"' -f4 || true)

        CURRENT_VERSION="none"
        if command -v agy >/dev/null 2>&1; then
            CURRENT_VERSION=$(agy --version 2>/dev/null | head -n1 || true)
        fi

        echo "Current local version : $CURRENT_VERSION"
        echo "Latest Google release : ${REMOTE_VERSION:-unknown}"

        if [ -n "$REMOTE_VERSION" ] && [ "$CURRENT_VERSION" != "$REMOTE_VERSION" ] && [ -n "$REMOTE_URL" ]; then
            echo "--> Newer version detected. Updating Antigravity CLI to $REMOTE_VERSION..."
            TMP_TGZ=$(mktemp /tmp/agy_update.XXXXXX.tar.gz)
            TMP_EXTRACT=$(mktemp -d /tmp/agy_extract.XXXXXX)
            if curl -fsSL "$REMOTE_URL" -o "$TMP_TGZ"; then
                tar -xzf "$TMP_TGZ" -C "$TMP_EXTRACT"
                INSTALL_BIN=$(find "$TMP_EXTRACT" -type f \( -name agy -o -name antigravity \) -perm /111 2>/dev/null | head -n1 || true)
                if [ -n "$INSTALL_BIN" ]; then
                    mv "$INSTALL_BIN" /usr/local/bin/agy
                    chmod 755 /usr/local/bin/agy
                    echo "--> Successfully updated Antigravity CLI to $REMOTE_VERSION"
                else
                    echo "Warning: Could not locate 'agy' or 'antigravity' binary in update archive."
                fi
                rm -rf "$TMP_TGZ" "$TMP_EXTRACT"
            else
                echo "Warning: Failed to download update archive from $REMOTE_URL."
                rm -rf "$TMP_TGZ" "$TMP_EXTRACT"
            fi
        else
            echo "Antigravity CLI is up to date."
        fi
    else
        echo "Notice: Could not check Google release manifest (offline or rate limited). Proceeding."
    fi
}

# Run initial update check
update_antigravity || true

echo "=== Google Antigravity Version ==="
if command -v agy >/dev/null 2>&1; then
    agy --version || true
else
    echo "Warning: 'agy' command not found in PATH."
fi

# Background auto-updater (every 24 hours)
if [ "$AUTO_UPDATE" = "true" ]; then
    (
        while true; do
            sleep 86400
            update_antigravity || true
        done
    ) &
    UPDATER_PID=$!
fi

# Check for authentication
is_authenticated() {
    # Check for API key
    if [ -n "${GEMINI_API_KEY:-}" ]; then
        return 0
    fi
    # Check for OAuth token files
    if [ -f "$CONFIG_DIR/.gemini/antigravity-cli/antigravity-oauth-token" ] || \
       [ -f "$CONFIG_DIR/.gemini/oauth_creds.json" ] || \
       [ -f "$CONFIG_DIR/.gemini/credentials.json" ]; then
        return 0
    fi
    return 1
}

# Graceful termination handler
cleanup() {
    echo "Received termination signal. Shutting down Antigravity daemon..."
    if [ -n "${UPDATER_PID:-}" ]; then
        kill "$UPDATER_PID" 2>/dev/null || true
    fi
    if [ -n "${DAEMON_PID:-}" ]; then
        kill "$DAEMON_PID" 2>/dev/null || true
    fi
    if [ -n "${WAIT_PID:-}" ]; then
        kill "$WAIT_PID" 2>/dev/null || true
    fi
    if command -v agy >/dev/null 2>&1; then
        if [ "$(id -u)" = "0" ]; then
            su - "$APP_USER" -c "HOME='$CONFIG_DIR' PATH='$PATH' agy remote-control stop" 2>/dev/null || true
        else
            agy remote-control stop 2>/dev/null || true
        fi
    fi
    echo "Container stopped cleanly."
    exit 0
}

trap cleanup SIGTERM SIGINT SIGHUP

# If custom command passed, execute as APP_USER
if [ "$#" -gt 0 ] && [ "$1" != "daemon" ]; then
    echo "Executing custom command as $APP_USER: $*"
    if [ "$(id -u)" = "0" ]; then
        exec sudo -E -u "$APP_USER" env HOME="$CONFIG_DIR" PATH="$PATH" "$@"
    else
        exec "$@"
    fi
fi

# Starting daemon mode
echo "=== Starting Antigravity CLI Daemon Mode ==="

if ! is_authenticated; then
    echo ""
    echo "======================================================================"
    echo " [ACTION REQUIRED] Google Antigravity CLI is not authenticated!"
    echo "----------------------------------------------------------------------"
    echo " The container is running in waiting mode so you can log in."
    echo ""
    echo " 1. Open a terminal to this container:"
    echo "    - Docker / CasaOS / Portainer:"
    echo "      docker exec -it antigravity agy"
    echo "    - Unraid WebGUI: click the container icon and select 'Console'"
    echo "      then run: agy"
    echo ""
    echo " 2. Copy the Google authentication URL into your browser to log in."
    echo " 3. Paste the verification code back into the terminal."
    echo " 4. All tokens and sessions will be saved to your /config volume."
    echo "    The daemon will automatically start as soon as login is complete."
    echo "======================================================================"
    echo ""
    echo "Waiting for authentication (run 'docker exec -it antigravity agy' to log in)..."

    while ! is_authenticated; do
        sleep 3 &
        WAIT_PID=$!
        wait "$WAIT_PID" 2>/dev/null || true
    done

    echo "--> Authentication detected! Proceeding with daemon startup..."

    # Ensure correct ownership of newly generated tokens
    if [ "$(id -u)" = "0" ]; then
        chown -R "$PUID:$PGID" "$CONFIG_DIR" 2>/dev/null || true
        chmod -R u+rwX,go+rX "$CONFIG_DIR" 2>/dev/null || true
    fi
fi

# Set the instance name in settings first
if [ -n "$ANTIGRAVITY_INSTANCE_NAME" ] && command -v agy >/dev/null 2>&1; then
    echo "Setting instance name to: $ANTIGRAVITY_INSTANCE_NAME"
    if [ "$(id -u)" = "0" ]; then
        su - "$APP_USER" -c "HOME='$CONFIG_DIR' PATH='$PATH' agy remote-control start --name '$ANTIGRAVITY_INSTANCE_NAME' --session" >/dev/null 2>&1 || true
    else
        agy remote-control start --name "$ANTIGRAVITY_INSTANCE_NAME" --session >/dev/null 2>&1 || true
    fi
fi

# Start remote control daemon directly in foreground if requested
if [ "$AUTO_START_DAEMON" = "true" ] && command -v agy >/dev/null 2>&1; then
    echo "Starting Antigravity Remote Control daemon directly (agy remote-control serve)..."
    echo "Antigravity CLI is running and ready. Connected to Antigravity Remote."
    if [ "$(id -u)" = "0" ]; then
        sudo -E -u "$APP_USER" env HOME="$CONFIG_DIR" PATH="$PATH" agy remote-control serve &
    else
        agy remote-control serve &
    fi
    DAEMON_PID=$!
    wait "$DAEMON_PID" 2>/dev/null || true
    echo "Notice: Antigravity Remote Control daemon exited."
fi

echo "Antigravity CLI container is running in idle loop. Press Ctrl+C or stop container to terminate."

# Keep container alive and responsive to traps
while true; do
    sleep 3600 &
    WAIT_PID=$!
    wait "$WAIT_PID" 2>/dev/null || true
done
