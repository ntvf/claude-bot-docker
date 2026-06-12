# claude-bot-docker

Secure Docker image for running [Claude Code](https://claude.ai/code) as a persistent Telegram bot.

## Features

- **Secure isolation** — runs via [Sysbox](https://github.com/nestybox/sysbox) (`sysbox-runc`) for true container isolation without `--privileged`
- **Persistent state** — Claude credentials, plugin cache, and conversation history survive restarts via a named volume
- **Telegram bridge** — uses the official `telegram@claude-plugins-official` plugin
- **Chromium ready** — all Playwright/Chromium system libs pre-installed
- **Non-root** — Claude runs as a non-root user (required for `--dangerously-skip-permissions`)

## Requirements

- Docker with [Sysbox](https://github.com/nestybox/sysbox) runtime installed
- A Telegram bot token from [@BotFather](https://t.me/BotFather)

## Setup

```bash
# 1. Build
docker compose build

# 2. First-time interactive setup (authenticate + install plugin)
docker run -it --rm --runtime=sysbox-runc -v claude-bot-docker_claude-home:/home/claude claude-bot-docker-claude-telegram claude

# Inside Claude:
# > /plugin install telegram@claude-plugins-official
# > /telegram:configure <YOUR_BOT_TOKEN>
# Exit, then DM your bot — it replies with a pairing code
# Re-enter and: /telegram:access pair <code>
# > /telegram:access policy allowlist

# 3. Start as daemon
docker compose up -d
```

## Persistent service (systemd)

```ini
[Unit]
Description=Claude Code Telegram Bot
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10
ExecStart=/usr/bin/docker run --rm --runtime=sysbox-runc \
  --name claude-telegram \
  --memory=4g \
  --pids-limit=500 \
  -v claude-bot-docker_claude-home:/home/claude \
  claude-bot-docker-claude-telegram:latest
ExecStop=/usr/bin/docker stop claude-telegram

[Install]
WantedBy=multi-user.target
```

## Update bot token

```bash
# Enter the running container and reconfigure
docker exec -it claude-telegram claude
# Then: /telegram:configure <NEW_TOKEN>
```

## Notes

- `CLAUDE.md` at `/home/claude/CLAUDE.md` is auto-loaded — use it to give Claude environment-specific instructions (e.g. Playwright `--no-sandbox` flag)
- Chromium launched via Playwright must use `--no-sandbox` and `--disable-dev-shm-usage` inside the container
