---
name: overhead-flights
description: >
  Install and run Overhead Flights — a minimal macOS screensaver (and optional
  fullscreen app / web preview) that shows the nearest aircraft overhead using
  live ADS-B data. Use when the user says 頭頂航班, Overhead Flights, install
  screensaver, 螢幕保護程式, or wants to set up this project for themselves or a friend.
---

# Overhead Flights — Agent Skill

## What this is

A **macOS Screen Saver** (`.saver`) that replaces screensaver **content** with a quiet black display of the nearest overhead flight.  
User keeps their own **start delay** (e.g. 20 minutes) in System Settings.

Also available:

- Fullscreen **App** (manual open; mouse/key to quit)
- **Web** preview via local server

## Hard rules (do not violate)

1. **Do not** install idle-watch LaunchAgents that open an App on idle — that fights System Settings.
2. **Do not** set `idleTime` to 0 to “win” over Apple landscape savers.
3. **Do** install `OverheadFlights.saver` and let the user pick it under **自訂 / Custom**.
4. **Do** leave start timing to System Settings (or only set `moduleDict` if asked).
5. Non-commercial / portfolio use; respect airplanes.live & adsbdb terms.

## Prerequisites

- macOS 12+
- Xcode (for `.saver` build)
- Network (live flight data)

## Install screensaver (primary path)

Run from repo root (`overhead-flights/` or `overhead flights/`):

```bash
cd macos
chmod +x build-and-install.sh
./build-and-install.sh
```

This:

1. Copies `index.html` (+ icon/manifest) into `macos/Web`
2. Builds `OverheadFlights.saver`
3. Installs to `~/Library/Screen Savers/OverheadFlights.saver`
4. Installs `thumbnail.tiff` for Settings grid

Then tell the user (Traditional Chinese OK):

1. 系統設定 → 背景圖片 → 更改螢幕保護程式  
2. **使用螢幕保護程式 → 自訂**  
3. 選 **OverheadFlights**（與 Fliqlo 同一區，往下找）  
4. **啟動時間**維持自己要的（例如 20 分鐘）— 不要亂改  
5. 若縮圖舊：重開系統設定，或先點別的再點回  

Gatekeeper / quarantine:

```bash
xattr -dr com.apple.quarantine ~/Library/Screen\ Savers/OverheadFlights.saver
```

## Optional: fullscreen App

```bash
cd macos-app
chmod +x build-app.sh
./build-app.sh
```

Opens `/Applications/Overhead Flights.app` (fullscreen; move mouse or press key to quit).

## Optional: web preview

```bash
python3 -m http.server 8765
# open http://localhost:8765 — use F11 for fullscreen
```

Needs localhost or https for geolocation.

## Verify

| Check | How |
|-------|-----|
| Saver installed | `ls ~/Library/Screen\ Savers/OverheadFlights.saver` |
| Thumbnail present | `ls .../Contents/Resources/thumbnail.tiff` |
| In Settings list | 自訂 → OverheadFlights visible |
| Live data | After saver starts full-screen, a nearby flight may appear (or black if none) |
| Timing preserved | Start delay still user’s value (e.g. 20 min) |

## Data sources

| Role | API |
|------|-----|
| Aircraft positions | `https://api.airplanes.live/v2/point/{lat}/{lon}/{radius_nm}` |
| Route / airline | `https://api.adsbdb.com/v0/callsign/{cs}` |

Native saver injects location via:

```js
window.__OVERHEAD_FIXED_POS__ = { lat, lon };
window.__overheadApplyNativePos?.();
```

## Project layout

- `index.html` — all UI + data logic  
- `macos/` — ScreenSaver target + `build-and-install.sh`  
- `macos-app/` — optional App  
- `docs/overhead-flights-spec.md` — product spec  

## Sharing with friends (what agent should prepare)

1. Repo on GitHub with this `SKILL.md` + `README.md`  
2. Friend: clone → tell AI “用 overhead-flights skill 幫我安裝螢保”  
3. Agent runs `macos/build-and-install.sh` and walks through 自訂 selection  
4. Note: unsigned binary may need Control-click → Open / Privacy allow  

## Do not

- Reintroduce `install-as-screensaver.sh` idle agent as the “main” product  
- Promise Windows `.scr`  
- Claim commercial license without checking API ToS  
