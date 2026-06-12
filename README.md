# claude-bot-docker

Secure Docker image for running [Claude Code](https://claude.ai/code) as a persistent Telegram bot.

## Features

- **Secure isolation** — [Sysbox](https://github.com/nestybox/sysbox) runtime, no `--privileged`
- **Persistent state** — credentials, plugin cache, history survive rebuilds via named volume
- **Extended Telegram bot** with control commands and inline action buttons after every reply
- **Chromium + Playwright** system libs pre-installed
- **Java 25 + Maven** available
- **Passwordless sudo** — Claude can install system packages (`sudo apt-get install`)
- **Auto-update** — GitHub webhook triggers rebuild + restart on push to `main`

## Bot commands

| Command | Description |
|---------|-------------|
| `/stop` | ⏹ Interrupt current task (SIGINT) |
| `/compact` | 🗜 Compact the context window |
| `/clear` | 🆕 Clear conversation history |
| `/usage` | 📊 Context window % and token counts |
| `/model` | Switch model (sonnet / opus / haiku) |
| `/goal <text>` | 🎯 Set persistent goal prepended to every message |
| `/goal clear` | Remove the current goal |
| `/status` | Check pairing state |

Every Claude reply includes **[⏹ Stop] [🗜 Compact] [🆕 Clear] [📊 Usage]** inline buttons.

## Systemd service

```ini
# /etc/systemd/system/claude-telegram.service
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
  -v claude-telegram_claude-home:/home/claude \
  claude-telegram-claude-telegram:latest
ExecStop=/usr/bin/docker stop claude-telegram

[Install]
WantedBy=multi-user.target
```

## Auto-update (polling, NAT-friendly)

Polls GitHub every 5 minutes and rebuilds + restarts on new commits to `main`. No inbound ports required.

```bash
# 1. Install files
cp auto-update/claude-telegram-updater.service /etc/systemd/system/
cp auto-update/claude-telegram-updater.timer   /etc/systemd/system/
chmod +x auto-update/poll-update.sh

# 2. Enable
systemctl daemon-reload
systemctl enable --now claude-telegram-updater.timer

# Check status
systemctl list-timers claude-telegram-updater
```

**Is it safe?** Only your repo is polled. Since the container runs in Sysbox, a malicious Dockerfile `RUN` step can't escape to the host — but it could run arbitrary commands during `docker build` on the host layer. Keep push access to `main` controlled.

## First-time setup

```bash
# Build
docker build -t claude-telegram-claude-telegram:latest .

# One-time interactive setup — authenticate Claude and install the Telegram plugin
docker run -it --rm --runtime=sysbox-runc \
  -v claude-telegram_claude-home:/home/claude \
  claude-telegram-claude-telegram:latest bash

# Inside: run `claude`, then:
#   /plugin install telegram@claude-plugins-official
#   /telegram:configure <BOT_TOKEN>
# Exit, DM your bot, get the pairing code, re-enter and:
#   /telegram:access pair <code>
#   /telegram:access policy allowlist

# Start
systemctl start claude-telegram
```

## Notes

- `CLAUDE.md` at `/home/claude/CLAUDE.md` is auto-loaded — use it for environment-specific instructions
- Chromium via Playwright must use `--no-sandbox` and `--disable-dev-shm-usage` inside the container
- `sudo apt-get update && sudo apt-get install -y <pkg>` works (apt cache is cleared in image build)
