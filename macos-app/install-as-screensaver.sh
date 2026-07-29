#!/bin/bash
# Make Overhead Flights behave as the Mac screensaver:
# 1) Ensure the fullscreen App is installed
# 2) Install a background idle watcher (auto-starts after idle)
# 3) Re-install legacy .saver (for systems that still list it)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJ="$(cd "$ROOT/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/OverheadFlights"
AGENTS="$HOME/Library/LaunchAgents"
PLIST_SRC="$ROOT/com.portfolio.overheadflights.idle.plist"
PLIST_DST="$AGENTS/com.portfolio.overheadflights.idle.plist"
BIN="$SUPPORT/overhead-idle-watch"
IDLE_SECONDS="${1:-120}"  # default 2 minutes

echo "==> 1/3 Build fullscreen App"
"$ROOT/build-app.sh"

echo "==> 2/3 Build idle watcher (auto-start after ${IDLE_SECONDS}s idle)"
mkdir -p "$SUPPORT" "$AGENTS"
# Patch threshold into a temp copy of source if needed
TMP_SWIFT="$SUPPORT/idle-watch.swift"
sed "s/idleSecondsThreshold: Double = 120/idleSecondsThreshold: Double = ${IDLE_SECONDS}/" \
  "$ROOT/idle-watch.swift" > "$TMP_SWIFT"

swiftc -O \
  -framework AppKit -framework Foundation -framework IOKit \
  -target arm64-apple-macos12.0 \
  "$TMP_SWIFT" -o "$BIN"
chmod +x "$BIN"

# Install LaunchAgent
sed "s|__BINARY__|${BIN}|g" "$PLIST_SRC" > "$PLIST_DST"
launchctl bootout "gui/$(id -u)/com.portfolio.overheadflights.idle" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/com.portfolio.overheadflights.idle" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/com.portfolio.overheadflights.idle" 2>/dev/null || \
  launchctl load -w "$PLIST_DST" 2>/dev/null || true

echo "==> 3/3 Install classic .saver (optional; may not appear in Settings on new macOS)"
if [[ -x "$PROJ/macos/build-and-install.sh" ]]; then
  "$PROJ/macos/build-and-install.sh" || true
  # Point system moduleDict at our saver when user uses "Start Screen Saver"
  defaults -currentHost write com.apple.screensaver moduleDict -dict \
    moduleName "Overhead Flights" \
    path "$HOME/Library/Screen Savers/OverheadFlights.saver" \
    type 0 || true
fi

echo ""
echo "=========================================="
echo "  Overhead Flights = 你的螢幕保護行為"
echo "=========================================="
echo ""
echo "已啟用："
echo "  • 電腦約 ${IDLE_SECONDS} 秒沒動滑鼠/鍵盤 → 自動全螢幕顯示航班"
echo "  • 一動滑鼠或按鍵 → 結束"
echo "  • 登入後背景常駐（LaunchAgent）"
echo ""
echo "測試：兩分鐘內不要碰電腦，應會自動出現。"
echo "（想改成 5 分鐘：  $0 300  ）"
echo ""
echo "關閉自動螢保："
echo "  launchctl bootout gui/\$(id -u)/com.portfolio.overheadflights.idle"
echo "  rm -f ~/Library/LaunchAgents/com.portfolio.overheadflights.idle.plist"
echo ""
