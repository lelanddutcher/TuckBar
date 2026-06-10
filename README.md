<p align="center">
  <img src="design/tuckbar-social.png" alt="TuckBar — tuck your menu bar away on the displays you choose" width="100%">
</p>

# TuckBar

**Tuck your menu bar away — and pull it back the second you want it.**

TuckBar hides the macOS menu bar on the displays *you* choose, so it stops baking itself into your OLED panel and gets out of the way for a cleaner screen. Reach for the top edge and it slides right back.

It's the menu-bar equivalent of "auto-hide the Dock" — except macOS won't let you do that **per monitor**, and that's the whole point of TuckBar.

> Early days — v0.1, built in the open. Issues and ideas welcome.

## Why

The macOS menu bar is bright, static, and always-on. On an OLED (or any display you'd rather keep clean) that's two problems:

- **Burn-in fuel** — the same bright bar in the same pixels, hour after hour.
- **Visual clutter** — chrome you don't need while you're heads-down.

macOS *can* auto-hide the menu bar, but it's **all-or-nothing across every display**. TuckBar makes it **per-display**: tag the monitor you want kept clean (say, your OLED) and TuckBar tucks *its* menu bar while every other monitor keeps its bar exactly where it is.

## The trick: a real per-monitor menu bar

There's no public API to hide the menu bar on a single display, so TuckBar does it the honest way: it lays a thin cover over the tagged display's menu-bar strip and **fills it with that display's actual wallpaper pixels**, captured live with ScreenCaptureKit. The bar appears to simply vanish — the wallpaper runs clean to the top edge, no seam, no black band. Move your pointer up there and the cover steps aside so you can use the real bar; move away and it tucks back.

Prefer maximum burn-in protection over seamlessness? Flip the cover to **solid black** (pixels off), or use the slider to just **dim** the bar instead of hiding it.

> When the tagged display is your *only* screen, there's nowhere else to put the bar — so TuckBar falls back to the native system auto-hide (with the same hover-to-reveal) instead of covering it.

## Features

- **Per-display tagging** — tuck the menu bar on the displays you choose; the rest keep theirs.
- **Seamless or black** — a wallpaper-matched cover (looks like the bar's just gone) or pixels-off black, with a dim slider in between.
- **Hover to reveal** — the real menu bar comes back when you reach for it, then re-tucks when you leave.
- **Untuck** — need the bar for a while (a recording, a finicky app)? Untuck it for 5–60 minutes and it re-tucks itself.
- **Also hide the Dock** — optional, while a tagged display is connected.
- **Tuck on connect** — tucks automatically when a tagged display is plugged in, restores when it's unplugged.
- **Stays out of the way** — lives in the menu bar, opens at login if you want, and puts everything back when you quit.

## Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon or Intel

## Install

It's a tiny Swift package with no dependencies — build it yourself:

```bash
git clone https://github.com/lelanddutcher/TuckBar.git
cd TuckBar
./scripts/build-app.sh
open build/TuckBar.app
```

That assembles `build/TuckBar.app`; drag it to `/Applications` if you like.

> TuckBar is currently **ad-hoc signed** (not notarized), so the first time you open it you may need to right-click → **Open** to get past Gatekeeper.

## Permissions

TuckBar asks for these the first time it needs them:

- **Screen Recording** — to read the wallpaper pixels for the seamless cover. It captures only the menu-bar strip of the tagged display; nothing is recorded or saved. Without it, the cover simply falls back to black.
- **Automation (System Events)** — only for the single-display auto-hide fallback and the optional "also hide the Dock," driven the same way System Settings does it.

A seamless-on-a-second-monitor setup needs only Screen Recording; the rest is optional.

## How it works

- **Multiple displays** → a borderless cover window sits over the tagged display's menu-bar strip (above the menu-bar window level, on every Space), filled with the live wallpaper slice or black. A lightweight poll reveals it on hover and steps it aside under full-screen apps.
- **Single display** → native menu-bar auto-hide, so you're never left without a way to reach the bar.
- **Wallpaper capture** → ScreenCaptureKit grabs the Dock's per-display wallpaper window, clipped to the strip, and re-captures when the wallpaper or Space changes.
- **Restore** → quitting uncovers everything; if TuckBar is ever force-quit mid-tuck, it reconciles on next launch and restores the bar, so you're never stranded.

## Known limitations

- Hiding the bar on a *single* display uses the system auto-hide, which is global on that Mac — there's no per-display API for it.
- The seamless cover needs Screen Recording; without it you get the (still useful) black cover.
- Best-effort for dynamic / time-of-day wallpapers: it re-captures on change, but a slow same-image shift can lag by a moment.

## Building

```bash
swift build -c release        # compile
./scripts/build-app.sh        # assemble the signed .app bundle
swift build                   # debug build
```

The icon and social art regenerate from source (CoreGraphics, no external tools):

```bash
./scripts/make-icon.sh                          # → Resources/AppIcon.icns
swift scripts/make-thumbnail.swift out.png      # → social card
```

## License

MIT — see [LICENSE](LICENSE).
