#!/bin/bash
# Build CodexGauge.app from source with the Swift command-line toolchain (no Xcode GUI needed),
# wrap the binary into a proper .app bundle, ad-hoc sign it. Pass "run" to (re)launch after building.
set -e
cd "$(dirname "$0")"

echo "▸ swift build -c release …"
swift build -c release

APP="CodexGauge.app"
BIN=".build/release/CodexGauge"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN" "$APP/Contents/MacOS/CodexGauge"
cp -f Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] && cp -f AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP" >/dev/null
echo "▸ built ./$APP"

if [ "$1" = "run" ]; then
    pkill -x CodexGauge 2>/dev/null || true
    sleep 0.4
    open "$APP"
    echo "▸ launched (look at your menu bar)"
fi
