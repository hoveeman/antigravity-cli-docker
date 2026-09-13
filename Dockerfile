# ==============================================================================
# Google Antigravity CLI Container for Unraid & Docker Hosts
# Multi-Arch: linux/amd64, linux/arm64
# ==============================================================================

FROM ubuntu:24.04

LABEL maintainer="Trent (hoveeman)"
LABEL org.opencontainers.image.title="Antigravity CLI for Unraid"
LABEL org.opencontainers.image.description="Containerized Google Antigravity CLI with full developer toolchains for Unraid and Docker hosts"
LABEL org.opencontainers.image.source="https://github.com/hoveeman/antigravity-cli-docker"
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/config \
    PATH="/config/.local/bin:/usr/local/bin:$PATH"

# 1. Install base utilities, build toolchains, and Python 3
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    lsb-release \
    openssh-client \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    sudo \
    tar \
    tzdata \
    unzip \
    wget \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js LTS (v22.x) from official NodeSource repository
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# 3. Install Docker CLI (for Docker socket passthrough from host)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y --no-install-recommends docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# 4. Install official Google Antigravity CLI flat binary
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- -d /usr/local/bin && \
    chmod 755 /usr/local/bin/agy && \
    /usr/local/bin/agy --version || true

# 5. Create persistent mount points
RUN mkdir -p /config /workspaces && \
    chmod 777 /config /workspaces

# 6. Install entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspaces
VOLUME ["/config", "/workspaces"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["daemon"]
