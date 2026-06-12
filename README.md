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

## Auto-update (GitHub webhook)

Pushes to `main` automatically rebuild the image and restart the service.

```bash
# 1. Copy auto-update files
cp auto-update/claude-telegram-updater.service /etc/systemd/system/
cp auto-update/.env.example /opt/claude-telegram/auto-update/.env
# Edit .env — set GITHUB_WEBHOOK_SECRET

# 2. Enable
systemctl enable --now claude-telegram-updater

# 3. GitHub repo → Settings → Webhooks
#    URL: http://<server-ip>:9876/webhook
#    Content type: application/json
#    Secret: same as GITHUB_WEBHOOK_SECRET
#    Event: push
```

**Is it safe?** The webhook verifies GitHub's HMAC signature. Only pushes from your repo trigger a rebuild. Since the container runs in Sysbox, a malicious Dockerfile `RUN` step can't escape to the host — but it could still run arbitrary commands during `docker build` on the host layer. Keep your repo access controlled.

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
