#!/bin/bash
# Builds NotchSwitcher.app (menu-bar-less agent app) with swiftc; no SwiftPM or Xcode needed.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/NotchSwitcher.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
    Sources/NotchSwitcher/*.swift -o "$APP/Contents/MacOS/NotchSwitcher"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NotchSwitcher</string>
    <key>CFBundleIdentifier</key><string>dev.mustafa.notchswitcher</string>
    <key>CFBundleExecutable</key><string>NotchSwitcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSCameraUsageDescription</key><string>The mirror shows your camera feed.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
