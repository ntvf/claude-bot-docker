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

# Ensure CLAUDE.md has correct environment notes (rewrite known sections)
python3 - <<'PYEOF'
import os, re

CLAUDE_MD = os.path.expanduser('~/CLAUDE.md')
SECTIONS = {
    'Active MCP tools': 'Available MCP servers: **telegram** (reply/react/edit/download) and **google-surf** (web search via `mcp__google-surf__search`).',
    'Web search': 'ALWAYS use the **google-surf MCP** (`mcp__google-surf__search`) for any web search or URL fetch.\nNEVER use the built-in WebSearch tool — it is disabled.',
    'Formatting': 'Every reply is auto-converted to Telegram MarkdownV2 — write normal markdown. Use `**bold**`, `_italic_`, `` `code` ``, triple-backtick code blocks. Do NOT set `format` in the reply tool unless needed (default \'auto\' handles conversion). Use `format: "text"` only for fully literal content.',
}
try:
    content = open(CLAUDE_MD).read()
except FileNotFoundError:
    content = ''

for header, body in SECTIONS.items():
    section = f'\n## {header}\n{body}\n'
    pattern = rf'\n## {re.escape(header)}\n.*?(?=\n## |\Z)'
    if re.search(pattern, content, re.DOTALL):
        content = re.sub(pattern, section, content, flags=re.DOTALL)
    else:
        content += section

open(CLAUDE_MD, 'w').write(content)
PYEOF


SURF_CONFIG="$HOME/.claude/google-surf-mcp.json"
if [ ! -f "$SURF_CONFIG" ]; then
  printf '{"mcpServers":{"google-surf":{"command":"/usr/bin/google-surf-mcp","args":[]}}}\n' > "$SURF_CONFIG"
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

  BASE_CMD="claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official --mcp-config $SURF_CONFIG"

  if [ -n "$LATEST_SESSION" ]; then
    # Signal server.ts to inject "what is the status?" after bun starts
    [ -f /tmp/last_chat_id ] && cp /tmp/last_chat_id /tmp/send_status_on_start || true
    script -qfc "$BASE_CMD --resume $LATEST_SESSION" /dev/null
  else
    rm -f /tmp/send_status_on_start
    script -qfc "$BASE_CMD" /dev/null
  fi
  echo "[supervisor] Claude exited — restarting in 3s…"
  sleep 3
done
