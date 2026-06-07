# TuckBar

A tiny macOS menu-bar app that **tucks the menu bar (and Dock) away** to protect OLED
displays from burn-in — automatically, based on which display is connected.

> The notch is the pocket. Tuck the bar in.

Built for the real case: an Alienware **AW3225QF** (4K QD-OLED) plugged into a Mac. The
menu bar and Dock are the highest burn-in risk because they're static and bright.

## What it does

- **Two modes, switched by display:**
  - **Normally** (no protected display connected) → e.g. *Never Hidden* (laptop: bar stays out).
  - **When protected** (a tagged display is connected) → e.g. *Always Hidden* (tuck it).
- **Tag a display** to mark what triggers Protected mode; switching is automatic on connect/disconnect.
- **Snooze ("Untuck")** — temporarily reveal the bar for a set time (5–60 min) then auto-re-tuck.
  Built for apps like DaVinci Resolve where you live in the menus.
- **Also tuck the Dock** while protected (optional; restored afterward).
- Seamless — changes animate via System Events, no flash. **Open at login.**

## Build & run

```bash
bash scripts/build-app.sh      # compiles + assembles build/TuckBar.app
open build/TuckBar.app          # launches into the menu bar (no Dock icon)
```

Requires macOS 14+, Swift 6 toolchain (Xcode 16+). No external dependencies. First run
prompts once for **Automation** permission (to drive System Events) — click OK.

## macOS realities (honest constraints)

- **Menu-bar hide is global, not per-display.** No public API hides it on one monitor only.
  The model is therefore *"tagged display connected ⇒ tuck; gone ⇒ untuck."*
- **Live apply** uses System Events (`autohide menu bar of dock preferences`) +
  `killall ControlCenter`/`SystemUIServer` — instant and smooth. (The lazy `_HIHideMenuBar`
  preference write alone is too slow in an accessory app.)
- **No app-level full-screen pixel-shift.** The AW3225QF already pixel-shifts in hardware;
  software's job is the static chrome (hide/dim).

## Design

`design/tuckbar-icon-animations.html` — motion studies for the app icon (the bulge → tuck).

## Roadmap

See `ROADMAP.md`. Next candidates: global hotkey for "Untuck now", a production app icon,
and the "dim" mode (DDC brightness + a menu-bar dimming overlay).
