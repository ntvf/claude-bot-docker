#!/bin/bash
set -e

PLUGIN_DIR="$HOME/.claude/plugins/cache/claude-plugins-official/telegram/0.0.6"

# Apply patched server.ts if the plugin cache exists
if [ -d "$PLUGIN_DIR" ]; then
  cp /opt/server-patch.ts "$PLUGIN_DIR/server.ts"
fi

exec script -qfc "claude --dangerously-skip-permissions --channels plugin:telegram@claude-plugins-official" /dev/null
