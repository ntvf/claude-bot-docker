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

# Inject google-surf-mcp into settings.json mcpServers
python3 - <<'PYEOF'
import json, os
path = os.path.expanduser('~/.claude/settings.json')
try:
    cfg = json.load(open(path))
except Exception:
    cfg = {}
cfg.setdefault('mcpServers', {})['google-surf'] = {
    'command': 'npx',
    'args': ['-y', 'google-surf-mcp'],
    'env': {'SURF_CLOUD_MODE': 'true'}
}
# Allow the new MCP tool patterns
cfg.setdefault('permissions', {}).setdefault('allow', [])
allow = cfg['permissions']['allow']
if 'mcp__google-surf__*' not in allow:
    allow.append('mcp__google-surf__*')
# Remove WebSearch auto-allow so Claude prefers google-surf MCP
if 'WebSearch(*)' in allow:
    allow.remove('WebSearch(*)')
json.dump(cfg, open(path, 'w'), indent=2)
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
Use `format: "markdownv2"` in the reply tool for any response that contains code, lists, headers, or structured content. Telegram renders MarkdownV2: `*bold*`, `_italic_`, `` `inline code` ``, triple-backtick code blocks with language tag. Escape all literal special chars (`_*[]()~\`>#+-=|{}.!`) with a backslash when they appear outside formatting. For plain prose with no formatting, omit the format param (defaults to plain text).
MDEOF
fi

# Pre-warm google-surf-mcp headless Chrome profile (first boot only, takes ~35s)
if [ ! -d "$HOME/.google-surf-mcp/main" ]; then
  echo "[entrypoint] Pre-warming google-surf-mcp profile (waiting up to 60s)…"
  npx google-surf-mcp &
  SURF_PID=$!
  for i in $(seq 1 30); do
    sleep 2
    if [ -d "$HOME/.google-surf-mcp/main" ]; then
      echo "[entrypoint] google-surf-mcp profile ready after $((i*2))s"
      break
    fi
  done
  kill "$SURF_PID" 2>/dev/null || true
fi

while true; do
  script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" /dev/null
  echo "[supervisor] Claude exited — restarting in 3s…"
  sleep 3
done
