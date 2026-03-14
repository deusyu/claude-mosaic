#!/bin/bash
# Uninstall claude-mosaic
set -euo pipefail

PLIST_LABEL="com.claude.claude-mosaic"
PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# Find the binary (dev build or /Applications)
BINARY=""
for candidate in \
    "$(cd "$(dirname "$0")" && pwd)/.build/release/ClaudeMosaic" \
    "/Applications/Claude Mosaic.app/Contents/MacOS/ClaudeMosaic"; do
    if [[ -x "$candidate" ]]; then
        BINARY="$candidate"
        break
    fi
done

# 1. Unregister login item and hooks
if [[ -n "$BINARY" ]]; then
    "$BINARY" unregister 2>/dev/null || true
    "$BINARY" hooks-uninstall 2>/dev/null || true
fi

# 2. Remove legacy launchd plist if present
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
rm -f "$PLIST"

# 3. Kill running process
pkill -x ClaudeMosaic 2>/dev/null || true

# 4. Clean state files
rm -rf "$HOME/.claude/claude-mosaic"

# 5. Remove app bundle
for app in "/Applications/Claude Mosaic.app" "/Applications/ClaudeMosaic.app"; do
    if [[ -d "$app" ]]; then
        rm -rf "$app"
        echo "Removed $app"
    fi
done

echo "Uninstall complete."
