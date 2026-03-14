#!/bin/bash
# Uninstall claude-mosaic
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BINARY="$SCRIPT_DIR/.build/release/ClaudeMosaic"
PLIST_LABEL="com.claude.claude-mosaic"
PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# 1. Stop daemon
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
rm -f "$PLIST"
echo "Removed daemon."

# 2. Uninstall hooks
if [[ -x "$BINARY" ]]; then
    "$BINARY" hooks-uninstall
fi

# 3. Clean state files
rm -rf "$HOME/.claude/claude-mosaic"
echo "Cleaned state files."
echo "Uninstall complete."
