# TuckBar App Store assets

What is in this folder, Apple's specs, and how to rebuild each asset.

TuckBar ships on the **Mac App Store** (id6779300947). `scripts/release.sh` (Developer ID +
notarization) is kept as the fallback for direct distribution.

## Screenshots

`screenshots/` holds the current set: five 2560 × 1600 PNGs (16:10), the "dawn" look of the
light liquid-glass design. The App Store accepts 1280 × 800, 1440 × 900, 2560 × 1600 or
2880 × 1800, PNG or JPEG, 1 to 10 per localization.

The source is one HTML file, `design/appstore-v2/screens.html`, rendered with headless Chrome
so the glass can use a real backdrop blur:

```bash
bash scripts/render-store-screens.sh store/screenshots dawn   # or: daylight | oled
```

Open the HTML file in a browser with no hash to see all five frames; `#3` shows one frame,
`#3/daylight` one frame in a variant. The wallpaper in the frames is drawn in CSS, not taken
from macOS.

## App icon

**1024 × 1024 px** PNG, opaque artwork inside the rounded tile. Provided as
[`AppIcon-1024.png`](AppIcon-1024.png); the full ladder lives in `Resources/Assets.xcassets/`.

```bash
./scripts/make-icon.sh
```

## Listing copy

[`DESCRIPTION.md`](DESCRIPTION.md): name, subtitle, promotional text, description, keywords,
and What's New per version. Field limits: name ≤ 30, subtitle ≤ 30, promotional text ≤ 170,
keywords ≤ 100, description and What's New ≤ 4000.

## Building the upload

```bash
# bump MARKETING_VERSION / CURRENT_PROJECT_VERSION in project.yml first
bash scripts/release-appstore.sh        # -> build/appstore/TuckBar.pkg, upload with Transporter
```

Xcode must be signed in to the team account (PKUE74YS72) so `-allowProvisioningUpdates` can
refresh the provisioning profile. The script deletes `build/TuckBar.xcarchive` first, so move
a shipped archive somewhere safe before rerunning.

## Sources

- [Screenshot specifications, App Store Connect](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/)
- [App icons, Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/app-icons/)
