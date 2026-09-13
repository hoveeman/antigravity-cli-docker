# Antigravity CLI Docker Container & Unraid Application

- **Date**: 2026-09-13
- **Author**: Antigravity & hoveeman
- **Status**: Approved
- **Target Repositories**:
  - GitHub: `hoveeman/antigravity-cli-docker`
  - Docker Hub: `hoveeman/antigravity-cli`
  - GHCR: `ghcr.io/hoveeman/antigravity-cli`

---

## 1. Overview & Problem Statement

Users running Unraid NAS systems want to run the Google Antigravity CLI (`agy`) as an autonomous coding agent, accessible remotely from the Antigravity desktop application or web dashboard.

Installing Antigravity directly on bare-metal Unraid is unsuitable because:
1. Unraid runs its root filesystem in RAM (`tmpfs`), which wipes non-persistent terminal installations on reboot.
2. Unraid lacks `systemd` (it uses BSD/SysV-style init scripts), breaking the `systemd --user` service required by `agy remote-control start`.
3. Running an autonomous AI agent as bare-metal root exposes the storage array and flash drive (`/boot`) to accidental modifications.
4. Unraid NAS base OS lacks developer toolchains (Node.js, compilers, python-venv, etc.).

A containerized Docker solution resolves all of these issues by providing isolation, environment persistence, automatic updates directly from Google, and developer toolchains.

---

## 2. Architecture & Components

```
+-------------------------------------------------------------+
|                      Unraid Host                            |
|                                                             |
|  /mnt/user/appdata/antigravity   /mnt/user/projects         |
|             |                            |                  |
+-------------|----------------------------|------------------+
              | (Volume Mount)             | (Volume Mount)
              v                            v
+-------------------------------------------------------------+
|                  antigravity-cli Container                  |
|                                                             |
|   /config (Home Directory)      /workspaces                 |
|    - .gemini/ (OAuth tokens)     - Git repos & code         |
|    - .ssh/ (SSH keys)                                       |
|    - .gitconfig                                             |
|                                                             |
|   Runtimes & Toolchains:                                    |
|    - Google Antigravity CLI (/usr/local/bin/agy)            |
|    - Node.js LTS & npm                                      |
|    - Python 3, pip, python3-venv                            |
|    - Docker CLI (passthrough via /var/run/docker.sock)      |
|    - Build tools (gcc, g++, make, git, curl, jq)            |
|                                                             |
|   Services & Entrypoint:                                    |
|    - PUID/PGID user mapping (nobody:users / 99:100)         |
|    - Auto-update verification from Google on startup        |
|    - Periodic background update check                       |
|    - agy remote-control daemon launcher                     |
+-------------------------------------------------------------+
```

---

## 3. Detailed Specifications

### 3.1 Dockerfile (`Dockerfile`)
- **Base**: `ubuntu:24.04` (multi-arch `linux/amd64` and `linux/arm64`).
- **Dependencies**:
  - `curl`, `ca-certificates`, `git`, `jq`, `sudo`, `procps`, `openssh-client`, `tzdata`
  - `build-essential` (gcc, g++, make)
  - `python3`, `python3-pip`, `python3-venv`
  - Node.js LTS & npm via official NodeSource repository
  - `docker-ce-cli` via Docker official repository
- **Pre-installed CLI**: Google Antigravity CLI (`agy`) installed via `curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin` during image build.
- **Volumes**:
  - `/config`: Configuration, credentials, settings, user home directory.
  - `/workspaces`: Working directory for agent code and projects.
- **Entrypoint**: `/entrypoint.sh` with executable permissions.

### 3.2 Entrypoint Script (`entrypoint.sh`)
1. **User and Group Permissions**:
   - Accepts `PUID` (default: 99) and `PGID` (default: 100).
   - Dynamically configures a dedicated non-root user (`antigravity`) with the requested UID/GID or adjusts `/config` ownership.
   - Sets `$HOME` to `/config`.
   - Adds `/config/.local/bin` and `/usr/local/bin` to `$PATH`.
2. **Auto-Update Mechanism**:
   - If `AUTO_UPDATE=true` (default: `true`), checks Google's manifest endpoint (`https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_<arch>.json`) or re-executes Google's install script to update `agy` in `/usr/local/bin`.
   - Launches a background periodic timer (every 24 hours) to update `agy` if running for prolonged periods without restart.
3. **Authentication Check**:
   - Verifies if `/config/.gemini` or credentials exist.
   - If not authenticated, outputs a clear warning message instructing the user to open the container terminal / Unraid WebGUI console and run `agy` to complete OAuth login.
4. **Daemon Launch**:
   - If `AUTO_START_DAEMON=true` (default: `true`), runs:
     `agy remote-control start --name "${ANTIGRAVITY_INSTANCE_NAME:-unraid-server}" --session`
   - Keeps container alive with an idle wait (`tail -f /dev/null` or wait loop) responsive to termination signals (`SIGTERM`, `SIGINT`).

### 3.3 Unraid Community Applications Template (`templates/antigravity-cli.xml`)
- XML schema adhering to Unraid Community Applications standards.
- Metadata: Name, Author, Repository (`hoveeman/antigravity-cli:latest`), Registry, WebUI/Shell, Project, Support, Overview, Icon.
- Pre-configured paths:
  - Container Path: `/config` -> Host Path: `/mnt/user/appdata/antigravity`
  - Container Path: `/workspaces` -> Host Path: `/mnt/user/projects`
  - Container Path: `/var/run/docker.sock` -> Host Path: `/var/run/docker.sock` (optional)
- Pre-configured variables:
  - `PUID`: 99
  - `PGID`: 100
  - `TZ`: America/New_York
  - `ANTIGRAVITY_INSTANCE_NAME`: unraid-server
  - `AUTO_START_DAEMON`: true
  - `AUTO_UPDATE`: true

### 3.4 Docker Compose (`docker-compose.yml`)
- Standalone compose configuration for users running Docker Compose on Unraid, Ubuntu, or other Linux servers.
- Includes healthcheck and persistent volumes.

### 3.5 GitHub Actions CI/CD (`.github/workflows/docker-publish.yml`)
- Triggers: Push to `main`, release tags (`v*.*.*`), weekly scheduled cron, manual dispatch.
- Actions:
  - `docker/setup-qemu-action` (QEMU for ARM64 emulation)
  - `docker/setup-buildx-action`
  - `docker/login-action` for GHCR and Docker Hub
  - `docker/build-push-action` building platforms `linux/amd64,linux/arm64`
  - Conditional push to Docker Hub if secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` are present, always pushes to GHCR.

### 3.6 Documentation & Assets
- `README.md`:
  - Quickstart guide for Unraid (template installation, manual container creation, and docker-compose).
  - First-time authentication step-by-step with terminal walkthrough.
  - Connecting from Antigravity Desktop / Web UI.
  - Docker Hub and GHCR usage.
  - Configuration options table (environment variables, volumes).
  - Security considerations and Unraid permissions.
- `LICENSE`: MIT license.
- `.gitignore`: Ignoring local build caches, keys, and tokens.
- Icon asset in `assets/icon.png` referenced by the Unraid template.

---

## 4. Verification Plan

1. **Local Syntax & Script Verification**:
   - Validate `entrypoint.sh` with `bash -n` and shellcheck-style linting.
   - Verify XML well-formedness of `templates/antigravity-cli.xml` using `python3 -c "import xml.etree.ElementTree as ET; ET.parse('templates/antigravity-cli.xml')"`
   - Validate `docker-compose.yml` structure.
2. **Git & GitHub Integration**:
   - Initialize git repository.
   - Create public repository `hoveeman/antigravity-cli-docker` via `gh repo create`.
   - Push commit and verify remote repository status on GitHub.
