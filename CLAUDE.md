# TuckBar — working notes for agents

macOS menu-bar app. Tucks the menu bar away on the displays you tag, so a static bright
strip stops burning into an OLED, and brings it back the moment you reach the top edge.

## This repo is PUBLIC

`github.com/lelanddutcher/TuckBar` is public, and the app is **live on the Mac App Store**.

Never commit here:

- credentials, tokens, API keys, `.env` files, provisioning profiles, certificates
- strategy, roadmap-beyond-the-public-ROADMAP, competitive analysis
- session notes, working notes, research dossiers, handoff docs

Those belong in `~/Developer/.state/tuckbar/` — a private repo with no remote. The durable
state doc for this project is `~/Developer/.state/tuckbar/STATUS.md`; read it first.

**Never run `git add -A`.** It sweeps untracked scratch into a public branch. Always stage
explicit paths: `git add path/one path/two`.

A pre-commit hook runs `gitleaks protect --staged --redact`. It is verified blocking, but it
lives in `.git/hooks/`, so it is local-only and does **not** survive a fresh clone —
reinstall it after cloning.

## The Xcode project is generated — do not commit it

`project.yml` is the **source of truth**. `TuckBar.xcodeproj` is generated from it by
XcodeGen and is gitignored (`*.xcodeproj`). Never hand-edit the `.xcodeproj`, and never
commit it — the next `xcodegen generate` throws the edit away.

Change build settings, targets, entitlements wiring, or the version in `project.yml`, then:

```bash
xcodegen generate
```

Tracked build inputs, all of which the app cannot ship without:
`project.yml`, `TuckBar.entitlements`, `Resources/Info.plist`,
`Resources/Assets.xcassets/`, `scripts/release*.sh`, `scripts/ExportOptions*.plist`.

## Build and run

Day-to-day work uses SwiftPM — it is much faster than driving Xcode:

```bash
swift build                 # debug
swift build -c release
bash scripts/build-app.sh   # assemble a runnable build/TuckBar.app
```

There is no test target and no QA script. "Verified" means it built cleanly and you
observed the behaviour on a real display — say which you did.

For a dev build you can launch repeatedly without re-granting Screen Recording, sign with
the self-signed **"TuckBar Dev"** identity in the login keychain (ad-hoc signing changes the
code hash every build, so TCC treats each rebuild as a new app):

```bash
codesign --force --sign "TuckBar Dev" --identifier com.lelanddutcher.TuckBar build-dev/TuckBar.app
```

Kill the running app **before** copying a new binary over it, or `cp` fails with
"text file busy" *silently* and you end up testing a stale binary.

## Release

Two paths. The App Store is the shipping one; Developer ID is the fallback.

```bash
# Mac App Store: archive -> .pkg, then upload the .pkg with Transporter.
# (Xcode's own Organizer upload hangs at "sending analytics to App Store".)
bash scripts/release-appstore.sh

# Outside the App Store: archive -> Developer ID -> notarize -> staple -> zip
bash scripts/release.sh
```

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` first.

Neither script contains a credential. `release.sh` reads its notary credential from a
keychain profile via `$NOTARY_PROFILE` (default `TuckBar-Notary`); `release-appstore.sh`
signs through the Xcode-logged-in account with `-allowProvisioningUpdates`. Keep it that
way — if a script ever needs a secret, read it from the environment and put the real value
in `~/Developer/.state/tuckbar/`.

Team ID `PKUE74YS72` appears in `project.yml` and the ExportOptions plists. That is not a
secret; it ships in every signed build.

## Renaming traps

The folder was `MenuBarHide` until 2026-08-05. The GitHub repo has always been `TuckBar`.

Some `MenuBarHide` strings are **deliberate and load-bearing** — do not blanket
find-and-replace:

- `Sources/TuckBar/AppModel.swift` — `migrateFromMenuBarHideIfNeeded`, the
  `migratedFromMenuBarHide` flag, and the `com.lelanddutcher.MenuBarHide` UserDefaults
  suite migrate settings for users upgrading from the old bundle ID. Rewriting these
  silently breaks those users.
- `ROADMAP.md` records the rename as history.

## The marketing site is a different repo

`lelanddutcher/tuckbar-site` (private, Vite + Three.js, hosted on Cloudflare). It is
the one case that legitimately spans two repos — confirm before starting, keep the commits
separate, and do not touch its name or its redirects (`public/_redirects`).

## Voice

User-facing copy — README, site, App Store text — is terse, concrete, lowercase-leaning,
and uses **no em-dashes**. Match what is already there rather than inventing a new register.
