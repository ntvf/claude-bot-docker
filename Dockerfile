FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git ca-certificates bsdutils tmux unzip sudo wget \
    python3 python3-pip \
    ripgrep fd-find jq \
    postgresql-client sqlite3 \
    rsync imagemagick ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Playwright / Chromium system dependencies
RUN apt-get update && apt-get install -y \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2t64 libpango-1.0-0 libpangocairo-1.0-0 \
    libgtk-3-0 libglib2.0-0 fonts-liberation xvfb \
    && rm -rf /var/lib/apt/lists/*

# Java 25 (Temurin) + Maven
RUN curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | gpg --dearmor -o /usr/share/keyrings/adoptium.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb noble main" \
       > /etc/apt/sources.list.d/adoptium.list \
    && apt-get update && apt-get install -y temurin-25-jdk maven \
    && rm -rf /var/lib/apt/lists/*

# yq (YAML processor)
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# xh (modern HTTP client)
RUN XH_VER=$(curl -sfL https://api.github.com/repos/ducaale/xh/releases/latest | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])") \
    && curl -fsSL "https://github.com/ducaale/xh/releases/download/${XH_VER}/xh-${XH_VER}-x86_64-unknown-linux-musl.tar.gz" | tar -xz --strip-components=1 -C /usr/local/bin "xh-${XH_VER}-x86_64-unknown-linux-musl/xh"

# Python packages
RUN pip3 install --break-system-packages requests httpx beautifulsoup4

# Bun (required by telegram@claude-plugins-official MCP server)
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Claude Code + google-surf-mcp
RUN npm install -g @anthropic-ai/claude-code google-surf-mcp

# Non-root user with passwordless sudo — safe inside Sysbox isolation
RUN useradd -m -s /bin/bash claude \
    && echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Patched plugin server + entrypoint
COPY server-patch.ts /opt/server-patch.ts
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER claude
WORKDIR /home/claude

# Persist Claude state: credentials, plugin cache, conversation history
VOLUME ["/home/claude"]

# Entrypoint applies the patched server.ts then starts Claude with Telegram channel
CMD ["/entrypoint.sh"]
