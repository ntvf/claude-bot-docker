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

# Keep-alive pinger: periodically nudge the account so the rate-limit/session
# window stays active. Calls the API directly with the stored OAuth token
# (~9 tokens/ping) instead of `claude -p`, which loads the full agent harness
# (~20k cached tokens). Token is refreshed by the main session; on expiry the
# ping just gets a 401 (harmless).
keepalive() {
  local words=("hey" "hello" "hi" "thanks" "thank you" "yo" "good day" "cheers" "morning" "howdy")
  local lo="${KEEPALIVE_MIN:-300}" hi="${KEEPALIVE_MAX:-900}"
  local model="${KEEPALIVE_MODEL:-claude-haiku-4-5-20251001}"
  while true; do
    local wait=$(( RANDOM % (hi - lo + 1) + lo ))
    echo "[keepalive] next ping in ${wait}s"
    sleep "$wait"
    local w="${words[$RANDOM % ${#words[@]}]}"
    local tok
    tok=$(python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.claude/.credentials.json')))['claudeAiOauth']['accessToken'])" 2>/dev/null)
    if [ -z "$tok" ]; then echo "[keepalive] no token, skip"; continue; fi
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 https://api.anthropic.com/v1/messages \
      -H "authorization: Bearer $tok" \
      -H "anthropic-version: 2023-06-01" \
      -H "anthropic-beta: oauth-2025-04-20" \
      -H "content-type: application/json" \
      -d "{\"model\":\"$model\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"$w\"}]}" 2>/dev/null)
    echo "[keepalive] pinged '$w' -> HTTP $code"
  done
}
if [ "${KEEPALIVE_ENABLED:-true}" = "true" ]; then
  keepalive &
  echo "[keepalive] enabled — random ${KEEPALIVE_MIN:-300}-${KEEPALIVE_MAX:-900}s, model ${KEEPALIVE_MODEL:-claude-haiku-4-5-20251001}, direct API"
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
