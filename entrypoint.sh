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

# Configure google-surf-mcp in Claude Code global MCP settings
GLOBAL_MCP="$HOME/.claude/mcp.json"
if [ ! -f "$GLOBAL_MCP" ] || ! python3 -c "import json,sys; d=json.load(open('$GLOBAL_MCP')); sys.exit(0 if 'google-surf' in d.get('mcpServers',{}) else 1)" 2>/dev/null; then
  python3 - <<'PYEOF'
import json, os
path = os.path.expanduser('~/.claude/mcp.json')
try:
    cfg = json.load(open(path))
except Exception:
    cfg = {}
cfg.setdefault('mcpServers', {})['google-surf'] = {
    'command': 'npx',
    'args': ['-y', 'google-surf-mcp'],
    'env': {'SURF_CLOUD_MODE': 'true'}
}
json.dump(cfg, open(path, 'w'), indent=2)
PYEOF
fi

exec script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" /dev/null
