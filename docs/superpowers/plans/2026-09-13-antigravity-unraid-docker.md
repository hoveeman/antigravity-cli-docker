# Antigravity CLI Unraid Docker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a production-ready, multi-arch Docker container for running the Google Antigravity CLI on Unraid and standard Docker hosts, complete with Unraid Community Applications template, GitHub Actions CI/CD for Docker Hub/GHCR, and published to a public GitHub repository.

**Architecture:** A containerized Ubuntu 24.04 environment configured for Unraid PUID/PGID user mapping, preloaded with developer toolchains (Node.js, Python 3, Git, build-essential, Docker CLI) and official Google Antigravity CLI binary with auto-update on boot and remote-control daemon support.

**Tech Stack:** Docker, Bash, Ubuntu 24.04, Google Antigravity CLI (`agy`), GitHub Actions, Unraid XML Template Schema, Docker Compose.

**Spec:** `docs/superpowers/specs/2026-09-13-antigravity-unraid-docker-design.md`

## Global Constraints
- Target GitHub repository: `hoveeman/antigravity-cli-docker`
- Target Docker Hub repository: `hoveeman/antigravity-cli`
- Target GHCR repository: `ghcr.io/hoveeman/antigravity-cli`
- Base OS: `ubuntu:24.04`
- Default user mapping: `PUID=99`, `PGID=100` (nobody:users on Unraid)
- Volumes: `/config` (appdata/home), `/workspaces` (projects/shares)

---

### Task 1: Core Container Architecture & Entrypoint

**Files:**
- Create: `Dockerfile`
- Create: `entrypoint.sh`
- Create: `.dockerignore`
- Test: `tests/test_entrypoint.sh`

**Interfaces:**
- Consumes: Google release manifest / `install.sh`, environment variables (`PUID`, `PGID`, `ANTIGRAVITY_INSTANCE_NAME`, `AUTO_START_DAEMON`, `AUTO_UPDATE`)
- Produces: Executable container image with persistent configuration in `/config` and workspace in `/workspaces`

- [ ] **Step 1: Create test script for entrypoint logic**
  Write a shell test script verifying syntax, default environment handling, and permission routines.
- [ ] **Step 2: Run test script to verify failure / missing files**
  Run: `bash tests/test_entrypoint.sh`
- [ ] **Step 3: Create `Dockerfile`, `entrypoint.sh`, and `.dockerignore`**
  Implement the container specification with Ubuntu 24.04, Node.js, Python 3, build tools, Docker CLI, and entrypoint script with PUID/PGID support and agy updater.
- [ ] **Step 4: Run entrypoint validation and syntax checks**
  Run: `bash -n entrypoint.sh && bash tests/test_entrypoint.sh`
- [ ] **Step 5: Commit**
  `git add Dockerfile entrypoint.sh .dockerignore tests/ && git commit -m "feat: add Dockerfile and entrypoint script"`

---

### Task 2: Unraid Community Applications Template

**Files:**
- Create: `templates/antigravity-cli.xml`
- Create: `assets/icon.svg` (and PNG if needed)
- Test: `tests/test_template.py`

**Interfaces:**
- Consumes: Docker Hub repository `hoveeman/antigravity-cli:latest`
- Produces: XML template adhering to Unraid Community Applications standards

- [ ] **Step 1: Write template validation test**
  Write a python test checking XML structure, required tags (Name, Repository, Registry, Config paths, Variables).
- [ ] **Step 2: Run test to verify it fails**
  Run: `python3 tests/test_template.py`
- [ ] **Step 3: Implement `templates/antigravity-cli.xml` and generate app icon**
  Create valid Unraid XML template and asset icon.
- [ ] **Step 4: Run test to verify it passes**
  Run: `python3 tests/test_template.py`
- [ ] **Step 5: Commit**
  `git add templates/ assets/ tests/test_template.py && git commit -m "feat: add Unraid Community Applications template and assets"`

---

### Task 3: Docker Compose & Configuration Examples

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`
- Test: Syntax check on compose file

- [ ] **Step 1: Create `docker-compose.yml` and `.env.example`**
  Provide turn-key configuration for Docker Compose Manager on Unraid or standalone Docker hosts.
- [ ] **Step 2: Verify docker compose syntax**
  Validate yaml structure with python yaml parser.
- [ ] **Step 3: Commit**
  `git add docker-compose.yml .env.example && git commit -m "feat: add docker-compose configuration and env example"`

---

### Task 4: GitHub Actions CI/CD Workflow

**Files:**
- Create: `.github/workflows/docker-publish.yml`

**Interfaces:**
- Consumes: GitHub Actions secrets `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, and `GITHUB_TOKEN`
- Produces: Multi-arch builds (`linux/amd64`, `linux/arm64`) pushed to GHCR and Docker Hub

- [ ] **Step 1: Create workflow file**
  Configure multi-arch buildx action, GHCR login, Docker Hub login (conditional), semantic tagging, and scheduled cron.
- [ ] **Step 2: Verify workflow YAML syntax**
  Run python yaml check to verify `.github/workflows/docker-publish.yml`.
- [ ] **Step 3: Commit**
  `git add .github/ && git commit -m "ci: add multi-arch docker publish workflow"`

---

### Task 5: Documentation & License

**Files:**
- Create: `README.md`
- Create: `LICENSE`
- Create: `.gitignore`

- [ ] **Step 1: Create `README.md` with complete Unraid & Docker documentation**
  Include full instructions: Unraid installation (CA template and manual), OAuth authentication flow, Antigravity Remote connection, volume mappings, and environment variables.
- [ ] **Step 2: Create `LICENSE` (MIT) and `.gitignore`**
- [ ] **Step 3: Commit**
  `git add README.md LICENSE .gitignore && git commit -m "docs: add comprehensive README and MIT license"`

---

### Task 6: Repository Verification & GitHub Publishing

- [ ] **Step 1: Run all test validations**
  Run `bash tests/test_entrypoint.sh` and `python3 tests/test_template.py`.
- [ ] **Step 2: Create public GitHub repository via `gh`**
  Run `gh repo create hoveeman/antigravity-cli-docker --public --source=. --remote=origin --push`
- [ ] **Step 3: Verify GitHub repository and publish status**
  Verify remote URL, commit log, and GitHub visibility.
