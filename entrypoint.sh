#!/bin/bash
set -e

PLUGIN_CACHE="$HOME/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6"
PLUGIN_MKT="$HOME/.claude/plugins/marketplaces/claude-plugins-official/external_plugins/telegram"

MCP_PATCH='{"mcpServers":{"telegram":{"command":"bash","args":["-c","set -a; source $HOME/.claude/channels/telegram/.env; set +a; cd $HOME/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6 && exec bun server.ts"]}}}'

# Apply patched server.ts
if [ -d "$PLUGIN_CACHE" ]; then
  cp /opt/server-patch.ts "$PLUGIN_CACHE/server.ts"
fi

# Patch both .mcp.json files to use the working bash wrapper
for MCP_FILE in "$PLUGIN_CACHE/.mcp.json" "$PLUGIN_MKT/.mcp.json"; do
  if [ -f "$MCP_FILE" ]; then
    echo "$MCP_PATCH" > "$MCP_FILE"
  fi
done

# Write minimal CLAUDE.md (overwrites every start to stay current)
cat > "$HOME/CLAUDE.md" <<'MDEOF'
## Environment
Telegram bot. Replies only reach the user via the `reply` tool — use `chat_id` from the inbound message. Every reply is auto-converted to MarkdownV2: write normal markdown (`**bold**`, `_italic_`, `` `code` ``, fenced code blocks). Default `format` is `auto`; only set `format: "text"` for fully literal content.
MDEOF

# Keep-alive pinger: periodically nudge Claude with a tiny prompt so the
# rate-limit/session window stays active. Runs in a throwaway temp dir.
# --strict-mcp-config starts ZERO MCP servers, so it never spawns a second
# telegram bun server that would kill the running bot (same trick as /usage).
keepalive() {
  local words=("hey" "hello" "hi" "thanks" "thank you" "yo" "good day" "cheers" "morning" "howdy")
  while true; do
    sleep "${KEEPALIVE_INTERVAL:-1800}"
    local w="${words[$RANDOM % ${#words[@]}]}"
    local d; d="$(mktemp -d)"
    ( cd "$d" && timeout 60 claude --strict-mcp-config \
        --model "${KEEPALIVE_MODEL:-claude-haiku-4-5-20251001}" \
        -p "$w" >/dev/null 2>&1 ) || true
    rm -rf "$d" 2>/dev/null || true
    echo "[keepalive] pinged: $w"
  done
}
if [ "${KEEPALIVE_ENABLED:-true}" = "true" ]; then
  keepalive &
  echo "[keepalive] enabled — every ${KEEPALIVE_INTERVAL:-1800}s, model ${KEEPALIVE_MODEL:-claude-haiku-4-5-20251001}"
fi

while true; do
  SESSION_DIR="$HOME/.claude/projects/-home-claude"

  # /clear writes this marker — skip resume so session starts fresh
  SHOULD_RESUME=true
  if [ -f /tmp/claude_clear_session ]; then
    rm -f /tmp/claude_clear_session
    SHOULD_RESUME=false
  fi

  LATEST_SESSION=""
  if [ "$SHOULD_RESUME" = "true" ]; then
    LATEST_SESSION=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl 2>/dev/null || true)
  fi

  BASE_CMD="claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official"

  # launch.py gives Claude a TTY and explicitly dismisses the trust + bypass
  # prompts (the bypass default is "No, exit", so a blind Enter would quit).
  if [ -n "$LATEST_SESSION" ]; then
    [ -f /tmp/last_chat_id ] && cp /tmp/last_chat_id /tmp/send_status_on_start || true
    python3 /opt/launch.py $BASE_CMD --resume "$LATEST_SESSION"
  else
    rm -f /tmp/send_status_on_start
    python3 /opt/launch.py $BASE_CMD
  fi
  echo "[supervisor] Claude exited — restarting in 3s…"
  sleep 3
done
