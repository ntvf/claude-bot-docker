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

# Inject google-surf-mcp into settings.json and mcp.json
python3 - <<'PYEOF'
import json, os

SURF_ENTRY = {
    'command': '/usr/bin/google-surf-mcp',
    'args': [],
    'env': {'SURF_CLOUD_MODE': 'true'}
}

# settings.json
path = os.path.expanduser('~/.claude/settings.json')
try:
    cfg = json.load(open(path))
except Exception:
    cfg = {}
# google-surf removed — blocks Claude MCP init causing bun to never start
cfg.get('mcpServers', {}).pop('google-surf', None)
cfg.setdefault('permissions', {}).setdefault('allow', [])
allow = cfg['permissions']['allow']
if 'WebSearch(*)' in allow:
    allow.remove('WebSearch(*)')
json.dump(cfg, open(path, 'w'), indent=2)

# mcp.json — remove google-surf (settings.json is authoritative; dual entry breaks bun)
mcp_path = os.path.expanduser('~/.claude/mcp.json')
try:
    mcp = json.load(open(mcp_path))
    mcp.get('mcpServers', {}).pop('google-surf', None)
    json.dump(mcp, open(mcp_path, 'w'), indent=2)
except Exception:
    pass
PYEOF

# Ensure CLAUDE.md has correct environment notes (idempotent per section)
CLAUDE_MD="$HOME/CLAUDE.md"
if ! grep -q 'Active MCP tools' "$CLAUDE_MD" 2>/dev/null; then
cat >> "$CLAUDE_MD" <<'MDEOF'

## Active MCP tools
Available MCP servers: **telegram** (reply/react/edit/download) and **google-surf** (web search).
MDEOF
fi
if ! grep -q 'Web search' "$CLAUDE_MD" 2>/dev/null; then
cat >> "$CLAUDE_MD" <<'MDEOF'

## Web search
ALWAYS use the **google-surf MCP** (`mcp__google-surf__search`) for any web search or URL fetch.
NEVER use the built-in WebSearch tool — it is disabled. If google-surf is not yet connected, wait or inform the user rather than falling back to WebSearch.
MDEOF
fi
if ! grep -q 'Formatting' "$CLAUDE_MD" 2>/dev/null; then
cat >> "$CLAUDE_MD" <<'MDEOF'

## Formatting
Every reply is auto-converted to Telegram MarkdownV2 — just write normal markdown. Use `**bold**`, `_italic_`, `` `code` ``, triple-backtick code blocks. Do NOT set `format` in the reply tool unless you have a specific reason (default 'auto' handles conversion). Use `format: "text"` only for content that should be completely literal.
MDEOF
fi


while true; do
  # Resume latest session (survives crashes/restarts; after /clear the newest JSONL is the cleared one)
  SESSION_DIR="$HOME/.claude/projects/-home-claude"
  LATEST_SESSION=$(ls -t "$SESSION_DIR"/*.jsonl 2>/dev/null | head -1 | xargs -I{} basename {} .jsonl 2>/dev/null || true)

  if [ -n "$LATEST_SESSION" ]; then
    script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official --resume $LATEST_SESSION" /dev/null
  else
    script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" /dev/null
  fi
  echo "[supervisor] Claude exited — restarting in 3s…"
  sleep 3
done
