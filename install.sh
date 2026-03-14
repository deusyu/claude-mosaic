#!/bin/bash
# Install claude-mosaic: build, bundle .app, launch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
BINARY="$BUILD_DIR/ClaudeMosaic"
INSTALL_DIR="/Applications"
APP_NAME="Claude Mosaic.app"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME"
PLIST_LABEL="com.claude.claude-mosaic"

# 1. Build
echo "Building claude-mosaic..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

if [[ ! -x "$BINARY" ]]; then
    echo "Error: Build failed, binary not found at $BINARY"
    exit 1
fi

# 2. Stop existing app if running
osascript -e 'tell application "System Events" to set quitApp to name of every process whose name is "ClaudeMosaic"' \
          -e 'if quitApp is not {} then tell application "ClaudeMosaic" to quit' 2>/dev/null || true
sleep 0.5

# 3. Clean up old launchd daemon if present
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# 4. Create .app bundle in /Applications
echo "Installing to $APP_BUNDLE..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/ClaudeMosaic"
cp "$SCRIPT_DIR/Sources/ClaudeMosaic/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLISTEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.claude.mosaic</string>
    <key>CFBundleName</key>
    <string>Claude Mosaic</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Mosaic</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeMosaic</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLISTEOF

# 5. Refresh icon cache
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_BUNDLE" 2>/dev/null || true

# 6. Launch — app auto-registers login item and hooks on startup
open "$APP_BUNDLE"

echo "Installation complete. App installed to $APP_BUNDLE"
