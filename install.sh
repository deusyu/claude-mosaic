#!/bin/bash
# Install claude-mosaic: build, bundle .app, launch.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
BINARY="$BUILD_DIR/ClaudeMosaic"
APP_BUNDLE="$BUILD_DIR/ClaudeMosaic.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/ClaudeMosaic"
PLIST_LABEL="com.claude.claude-mosaic"

# 1. Build
echo "Building claude-mosaic..."
cd "$SCRIPT_DIR"
swift build -c release 2>&1

if [[ ! -x "$BINARY" ]]; then
    echo "Error: Build failed, binary not found at $BINARY"
    exit 1
fi

# 2. Create .app bundle
echo "Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BINARY" "$APP_BINARY"
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

echo "App bundle: $APP_BUNDLE"

# 3. Stop existing daemon if running
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

# 4. Launch — app auto-registers login item and hooks on startup
open "$APP_BUNDLE"

echo "Installation complete. App is running and will start at login."
