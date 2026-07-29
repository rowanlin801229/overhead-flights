#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$ROOT/.." && pwd)"
APP_NAME="Overhead Flights"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources/Web"
BUILD="$ROOT/build"

rm -rf "$APP_DIR" "$BUILD"
mkdir -p "$MACOS" "$RES" "$BUILD"

echo "==> Compile"
swiftc -O -parse-as-library \
  -framework Cocoa -framework WebKit -framework CoreLocation \
  -target arm64-apple-macos12.0 \
  "$ROOT/main.swift" \
  -o "$BUILD/OverheadFlights-arm64" 2>/dev/null || \
swiftc -O \
  -framework Cocoa -framework WebKit -framework CoreLocation \
  -target arm64-apple-macos12.0 \
  "$ROOT/main.swift" \
  -o "$BUILD/OverheadFlights-arm64"

# Also build x86_64 if possible and lipo
if swiftc -O \
  -framework Cocoa -framework WebKit -framework CoreLocation \
  -target x86_64-apple-macos12.0 \
  "$ROOT/main.swift" \
  -o "$BUILD/OverheadFlights-x86_64" 2>/dev/null; then
  lipo -create "$BUILD/OverheadFlights-arm64" "$BUILD/OverheadFlights-x86_64" -o "$MACOS/${APP_NAME}"
else
  cp "$BUILD/OverheadFlights-arm64" "$MACOS/${APP_NAME}"
fi
chmod +x "$MACOS/${APP_NAME}"

echo "==> Bundle resources"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$PROJ/index.html" "$RES/"
[[ -f "$PROJ/icon.svg" ]] && cp "$PROJ/icon.svg" "$RES/"
[[ -f "$PROJ/manifest.webmanifest" ]] && cp "$PROJ/manifest.webmanifest" "$RES/"

# Fix executable name in plist if needed - already set

echo "==> Install to /Applications"
DEST="/Applications/${APP_NAME}.app"
rm -rf "$DEST"
cp -R "$APP_DIR" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
codesign --force --deep --sign - "$DEST" 2>/dev/null || true

echo ""
echo "Installed: $DEST"
echo "Launching once for test..."
open "$DEST"
