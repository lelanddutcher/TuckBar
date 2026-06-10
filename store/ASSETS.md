# TuckBar — publishing assets & checklist

What's in this folder, the exact Apple specs (checked June 2026), and what you still need to ship.

## Two ways to ship

### 1. Direct distribution (recommended) — Developer ID + notarization
The realistic path for TuckBar. It drives **System Events** (Automation) to toggle the system menu-bar / Dock auto-hide and lays a window over the menu bar — all fine for a notarized, directly-distributed app, but awkward for the Mac App Store sandbox. Steps:

1. Sign with a **Developer ID Application** certificate (needs a paid Apple Developer Program membership, $99/yr).
2. **Notarize** — `xcrun notarytool submit TuckBar.zip --apple-id … --team-id … --wait`, then `xcrun stapler staple TuckBar.app`.
3. Distribute the `.app` (zipped, or in a `.dmg`) via GitHub Releases or your site. Gatekeeper passes with no right-click→Open dance.

> Today's build is **ad-hoc signed** (no cert), so users get the one-time right-click→Open. Notarization removes that.

### 2. Mac App Store — tougher fit
The sandbox + review is a hard fit: System Events automation needs a temporary-exception entitlement reviewers frequently reject, and toggling system settings / covering the menu bar are review-sensitive. Doable, not guaranteed. If you pursue it you'll need App Store Connect and the assets below.

## Asset specs (Apple, checked June 2026)

### App icon
- **1024 × 1024 px**, PNG. macOS uses the rounded-tile form — transparency *around* the tile is fine; the artwork itself must be opaque (no see-through regions).
- **Provided:** [`AppIcon-1024.png`](AppIcon-1024.png), plus the full 16→1024 ladder in [`../Resources/AppIcon.icns`](../Resources/AppIcon.icns) (the build embeds it).

### Screenshots — required, **16:10**, any one resolution of:
| Resolution | Note |
|---|---|
| 1280 × 800 | |
| 1440 × 900 | |
| **2560 × 1600** | ← provided (highest @2x; App Store auto-scales the rest) |
| 2880 × 1800 | |

- PNG or JPEG · 1–10 per localization.
- **Provided:** [`screenshots/`](screenshots/) at 2560 × 1600.

### Metadata field limits
Name ≤ 30 · Subtitle ≤ 30 · Promotional text ≤ 170 · Keywords ≤ 100 · Description ≤ 4000 · What's New ≤ 4000. Ready-to-paste copy: [`DESCRIPTION.md`](DESCRIPTION.md).

## Still on you
- A **Developer ID** (or App Store) signing identity + notarization — paid Apple Developer Program account.
- A **privacy policy URL** — required for the App Store; for direct distribution a one-liner is enough. (TuckBar collects nothing and phones home to nobody; the wallpaper capture stays on-device.)
- A **support URL** — the repo works: https://github.com/lelanddutcher/TuckBar

## Regenerating the assets
```bash
./scripts/make-icon.sh                              # → Resources/AppIcon.icns + 1024 preview
swift scripts/make-thumbnail.swift design/tuckbar-social.png
swift scripts/make-screenshots.swift store/screenshots   # → the 2560×1600 set
```

## Sources
- [Screenshot specifications — App Store Connect](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
- [App icons — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
