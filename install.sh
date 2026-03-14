#!/bin/bash
# Install claude-mosaic: build, bundle .app, start daemon, register hook.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
BINARY="$BUILD_DIR/ClaudeMosaic"
APP_BUNDLE="$BUILD_DIR/ClaudeMosaic.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/ClaudeMosaic"
PLIST_LABEL="com.claude.claude-mosaic"
PLIST="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"

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
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BINARY" "$APP_BINARY"

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

# 4. Create launchd plist — launch the .app binary
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BINARY</string>
    </array>
    <key>KeepAlive</key>
    <false/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/claude-mosaic.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-mosaic.err.log</string>
</dict>
</plist>
EOF

# 5. Start daemon
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Started daemon: $PLIST_LABEL"

# 6. Register SessionStart hook (use raw binary for CLI commands)
"$BINARY" hooks-install --command "$BINARY hook"
echo "Installation complete."
