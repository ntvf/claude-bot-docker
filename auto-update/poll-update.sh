#!/bin/bash
# Polls GitHub for changes on main branch, rebuilds and restarts if new commits found.
# Runs as a systemd oneshot service on a 5-minute timer.

set -e

REPO_DIR="${REPO_DIR:-/opt/claude-telegram}"
SERVICE="${SERVICE_NAME:-claude-telegram}"

git -C "$REPO_DIR" fetch origin main --quiet 2>/dev/null || exit 0

LOCAL=$(git -C "$REPO_DIR" rev-parse HEAD)
REMOTE=$(git -C "$REPO_DIR" rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
  exit 0
fi

echo "[claude-telegram-updater] New commit detected: $LOCAL -> $REMOTE, rebuilding..."
git -C "$REPO_DIR" pull origin main
docker build -t claude-telegram-claude-telegram:latest "$REPO_DIR"
systemctl restart "$SERVICE"
echo "[claude-telegram-updater] Done."
