# Design System: Overhead Flights

## Visual Theme

**Mood:** Night air over a city — dim room, idle Mac, lock screen clock already owns the top.
**Style:** Ambient typographic; no chrome, no cards, no icons.
**Density:** Extremely sparse. One vertical stack, centered optically below true center.

## Color

Strategy: **Restrained** — near-black field + silver neutrals only. No accent hue on v1 screensaver.

| Role | Approx | Notes |
|------|--------|--------|
| Field | `rgb(0.02, 0.02, 0.025)` | Near-black, tiny cool tint (not pure #000) |
| Callsign | white ~0.82 alpha | Soft silver, not pure white |
| Airline | white ~0.48 | Secondary |
| Meta | white ~0.34 | Tertiary |
| Monogram | white ~0.28 | Whisper; almost atmosphere |

No gradients on type. No glow. No glass.

## Typography

**Family:** SF Pro / system (Ultra Light callsign, Light secondary, Regular monogram mono).
**Scale (screen-relative):** callsign ≈ **10% of view height**, capped by width so ~7 glyphs fit.
**Ratios from callsign:**

| Role | Size | Weight | Tracking |
|------|------|--------|----------|
| Monogram | 0.20× | Regular mono | +0.28em |
| Callsign | 1.0× | UltraLight mono digits | +0.08em |
| Airline | 0.30× | Light | +0.06em |
| Meta | 0.24× | Light | +0.10em |

**Stack spacing (from callsign size):** mono→callsign 0.06×, callsign→airline 0.16×, airline→meta 0.10× (asymmetric rhythm).

## Layout

- Vertical `NSStackView`, center X.
- Optical Y: slightly **below** geometric center (`+6%` of height) so lock clock keeps the upper third.
- Side inset ≥ 6% width.
- No cards, no borders, no dividers.

## Motion

- Optional slow anti-burn-in drift of whole stack (~4–6px, multi-minute cycle).
- New flight: optional short opacity fade (≤0.4s, ease-out); same flight updates: none.
- Respect reduced motion: no drift.

## Components

### Live flight stack (screensaver)

Monogram / Callsign / Airline / Meta (alt · bearing). Empty = all hidden, field only.

### Settings preview stub

Static BA sample; smaller absolute sizes; same hierarchy idea.
