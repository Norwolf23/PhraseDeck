#!/bin/bash
# Builds PhraseDeck.app into ./build. Requires Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/PhraseDeck.app
rm -rf build
mkdir -p "$APP/Contents/MacOS"

echo "Compiling…"
swiftc -O -parse-as-library Sources/*.swift -o "$APP/Contents/MacOS/PhraseDeck"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PhraseDeck</string>
    <key>CFBundleIdentifier</key><string>com.gustav.phrasedeck</string>
    <key>CFBundleName</key><string>PhraseDeck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>PhraseDeck reads your phrase lists from Apple Notes.</string>
</dict>
</plist>
PLIST

codesign -fs - "$APP"
echo "Built $APP — install with: cp -R $APP /Applications/"
