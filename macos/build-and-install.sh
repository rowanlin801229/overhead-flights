#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WEB_SRC="$(cd "$ROOT/.." && pwd)"
WEB_DST="$ROOT/Web"
INSTALL_DIR="${HOME}/Library/Screen Savers"
BUILD_DIR="$ROOT/build"

echo "==> Sync web assets into macos/Web"
rm -rf "$WEB_DST"
mkdir -p "$WEB_DST"
cp "$WEB_SRC/index.html" "$WEB_DST/"
# Shader background only (behind native AppKit flight text)
if [[ -f "$WEB_SRC/shader-bg.html" ]]; then
  cp "$WEB_SRC/shader-bg.html" "$WEB_DST/"
fi
# Etheral Shadow assets (original mask + noise from Framer / 21st component)
if [[ -f "$ROOT/Assets/etheral-mask.png" ]]; then
  cp "$ROOT/Assets/etheral-mask.png" "$WEB_DST/"
  cp "$ROOT/Assets/etheral-noise.png" "$WEB_DST/"
  echo "    + etheral-mask.png / etheral-noise.png"
fi
# optional companions if present
for f in manifest.webmanifest icon.svg; do
  if [[ -f "$WEB_SRC/$f" ]]; then
    cp "$WEB_SRC/$f" "$WEB_DST/"
  fi
done

echo "==> Building OverheadFlights.saver"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$ROOT/OverheadFlights.xcodeproj" \
  -target OverheadFlights \
  -configuration Release \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR/out" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  build

SAVER="$BUILD_DIR/out/OverheadFlights.saver"
if [[ ! -d "$SAVER" ]]; then
  # fallback search
  SAVER="$(find "$BUILD_DIR" -name 'OverheadFlights.saver' -type d | head -1 || true)"
fi

if [[ -z "${SAVER}" || ! -d "$SAVER" ]]; then
  echo "Build failed: OverheadFlights.saver not found" >&2
  exit 1
fi

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/OverheadFlights.saver"
cp -R "$SAVER" "$INSTALL_DIR/"

# Settings grid thumbnail (same convention as Fliqlo: Resources/thumbnail.tiff)
if [[ -f "$ROOT/thumbnail.tiff" ]]; then
  cp "$ROOT/thumbnail.tiff" "$INSTALL_DIR/OverheadFlights.saver/Contents/Resources/thumbnail.tiff"
fi
if [[ -f "$ROOT/thumbnail.png" ]]; then
  cp "$ROOT/thumbnail.png" "$INSTALL_DIR/OverheadFlights.saver/Contents/Resources/thumbnail.png"
fi

# Drop quarantine if any
xattr -dr com.apple.quarantine "$INSTALL_DIR/OverheadFlights.saver" 2>/dev/null || true
codesign --force --deep --sign - "$INSTALL_DIR/OverheadFlights.saver" 2>/dev/null || true

echo ""
echo "Installed: $INSTALL_DIR/OverheadFlights.saver"
echo "Next:"
echo "  1. Open System Settings → Screen Saver"
echo "  2. Choose “Overhead Flights”"
echo "  3. Preview with Space, or set start time"
echo ""
echo "If it does not appear, log out/in once, or:"
echo "  killall ScreenSaverEngine 2>/dev/null; killall legacyScreenSaver 2>/dev/null; true"
