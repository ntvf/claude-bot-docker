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
if 'mcp__google-surf__*' not in cfg['permissions']['allow']:
    cfg['permissions']['allow'].append('mcp__google-surf__*')
json.dump(cfg, open(path, 'w'), indent=2)
PYEOF

exec script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" /dev/null
