#!/bin/bash
# Fix: stop Apple image screensaver fighting us; reinstall idle auto-start.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IDLE_SECONDS="${1:-90}"
SUPPORT="$HOME/Library/Application Support/OverheadFlights"
AGENTS="$HOME/Library/LaunchAgents"
LABEL="com.portfolio.overheadflights.idle"
BIN="$SUPPORT/overhead-idle-watch"
PLIST="$AGENTS/${LABEL}.plist"

echo "==> Rebuild App"
"$ROOT/build-app.sh" >/dev/null
# build-app opens the app for test — quit it so idle mode can work
sleep 1
osascript -e 'quit app "Overhead Flights"' 2>/dev/null || true
killall "Overhead Flights" 2>/dev/null || true

echo "==> Turn OFF system image screensaver (idleTime=0 = never)"
# Prevent Apple wallpaper/image screensaver from starting first
defaults -currentHost write com.apple.screensaver idleTime -int 0
# Also try lock screen delay leave alone

echo "==> Rebuild idle watcher (${IDLE_SECONDS}s)"
mkdir -p "$SUPPORT" "$AGENTS"
export OVERHEAD_IDLE_SECONDS="$IDLE_SECONDS"
# bake threshold into binary via env at compile isn't needed — runtime env in plist
swiftc -O \
  -framework AppKit -framework Foundation -framework IOKit \
  -target arm64-apple-macos12.0 \
  "$ROOT/idle-watch.swift" -o "$BIN"
chmod +x "$BIN"

# LaunchAgent with env
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${BIN}</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>OVERHEAD_IDLE_SECONDS</key>
		<string>${IDLE_SECONDS}</string>
	</dict>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>/tmp/overhead-flights-idle.log</string>
	<key>StandardErrorPath</key>
	<string>/tmp/overhead-flights-idle.err</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/${LABEL}" 2>/dev/null || true

# clear log
: > /tmp/overhead-flights-idle.log
echo "restarted watcher" >> /tmp/overhead-flights-idle.log

echo ""
echo "========================================"
echo "  已修好：系統圖片螢保已關閉"
echo "  約 ${IDLE_SECONDS} 秒不動 → 自動出航班"
echo "========================================"
echo ""
echo "請這樣測："
echo "  1. 關掉所有 Overhead Flights 視窗"
echo "  2. 手放開鍵盤滑鼠"
echo "  3. 等約 $((IDLE_SECONDS + 10)) 秒"
echo ""
echo "若又跑出風景圖：系統設定 → 鎖定畫面 / 螢幕保護程式"
echo "  把「啟動螢幕保護程式」設成「永不」"
echo ""
echo "看自動啟動紀錄：  tail -f /tmp/overhead-flights-idle.log"
echo ""
