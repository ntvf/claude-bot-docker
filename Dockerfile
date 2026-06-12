FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl git ca-certificates bsdutils tmux unzip \
    python3 python3-pip \
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

# Bun (required by telegram@claude-plugins-official MCP server)
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Non-root user — required for --dangerously-skip-permissions
RUN useradd -m -s /bin/bash claude
USER claude
WORKDIR /home/claude

# Persist Claude state: credentials, plugin cache, conversation history
VOLUME ["/home/claude"]

# Start Claude Code with the official Telegram channel plugin.
# The plugin MCP server (bun server.ts) is spawned automatically.
# Setup: inside the container run `claude`, then:
#   /plugin install telegram@claude-plugins-official
#   /telegram:configure <BOT_TOKEN>
#   /telegram:access pair <code>   (after messaging the bot)
CMD ["script", "-qfc", "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official", "/dev/null"]
