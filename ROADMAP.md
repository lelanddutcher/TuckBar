# TuckBar — Roadmap

## Vision
The **OLED-aware** menu-bar utility. Where Bartender/Ice/Hidden Bar *manage icons*,
TuckBar *protects the panel* — by tucking (hiding) or dimming the static, always-bright
chrome (menu bar + Dock) on displays you tag, automatically, when they're connected.

Brand: **the notch is the pocket** — tuck the bar in. Cheeky outside, calm and competent inside.

Two modes of one product:
- **Tuck (hide)** — remove the static chrome entirely (most effective prevention). ✅ shipped
- **Dim** — keep it visible but lower its luminance (for "always-on" users). ← headline differentiator, next

## Hard constraints (decided, not bugs)
- Menu-bar hide is **global**, not per-display → model is "tagged display connected ⇒ tuck; gone ⇒ untuck."
- **No app-level full-screen pixel-shift.** The AW3225QF already pixel-shifts + panel-refreshes in hardware; software's job is the static chrome, i.e. hide/dim.
- **Live apply is solved** via System Events (was the big early unknown).

## Phases

### Phase 0–1 — Foundation + auto-protect ✅ (v0.1, 2026-05-28)
Display detection, tag-to-protect, auto-switch, launch at login.

### Phase 2 — Make "tuck" solid ✅ (largely done, 2026-05-29)
- [x] Live-apply via System Events + `killall ControlCenter`/`SystemUIServer` — instant, no flash.
- [x] Dock via System Events too (`set autohide of dock preferences`) — killed the desktop flash.
- [x] **Normal vs Protected** two-mode model (replaced snapshot/restore + the conflict banner).
- [x] **Snooze / "Untuck"** — timed temporary reveal, auto re-tuck (5–60 min). For DaVinci Resolve.
- [x] UI pass + brand voice ("All tucked in", "Untuck", "Nothing tucked yet").
- [x] Renamed **MenuBarHide → TuckBar** (`com.lelanddutcher.TuckBar`, one-time settings migration).
- [ ] First-run onboarding: "Which display do you want to protect?" → tag it.
- [ ] **Production app icon** (from the bulge→tuck motion studies in `design/`).
- [ ] Global hotkey for "Untuck now" (reveal without opening the popover — pairs with Resolve).
- [x] **Per-display hide ✅ (2026-06-01)** — via a `MenuBarCover` overlay (the SkyLight per-display API is a no-op). Covers the OLED's bar, others keep theirs; native auto-hide fallback when it's the only display.
- [x] **Hover-reveal ✅ (2026-06-01)** — the cover auto-hides when the pointer hits the covered display's top edge (real bar usable), re-covers on leave. Makes the hidden/dimmed bar usable per-display (the overlay alone hid it for good).
- [x] **Wallpaper-match cover ✅ (2026-06-01)** — paints the desktop-wallpaper slice behind the bar (default) for a seamless "bar gone" look; black optional. Respects fill mode + per-Space wallpaper.
- [x] **Wallpaper auto-refresh ✅ (2026-06-01)** — cover re-matches within ~1s when you change your wallpaper on the same Space (throttled key-poll), plus a Light/Dark observer. Dynamic time-of-day wallpapers best-effort.
- [ ] Hide the cover over fullscreen apps on the protected display (known refinement).

### Phase 3 — "Dim" as the headline
- [ ] **DDC/CI brightness control** for the AW3225QF (lower OLED luminance; keep everything visible).
- [x] **Menu-bar dimming overlay ✅ (2026-06-01)** — delivered as part of the per-display cover: an opacity slider (1.0 = hidden/black, <1 = dimmed, clicks pass through). Per-display, which the global `…InsetAndAlpha` can't do.
- [ ] Idle-aware escalation (after N min idle → dim/hide; restore on activity).

### Stretch
- "OLED care" pixel-refresh sweep, burn-in exposure timer, auto-suggest likely-OLED displays,
  Shortcuts/CLI control, persist snooze across relaunch.

## Decision log
- **2026-06-01** — **Per-display menu bar** via overlay (`MenuBarCover`), not the OS — confirmed empirically there's no working native per-display API. A protected display gets a black (alpha 1) / dimmed (alpha <1) cover; others keep their bars. Single-display → native auto-hide fallback. Replaced the Normally/Protected `MenuBarVisibility` pickers with a hide↔dim opacity slider. This also shipped the per-display "dim" feature.
- **2026-05-29** — Name = **TuckBar** (`tuckbar.com` available; `.app` squatted-but-dead). Bundle id `com.lelanddutcher.TuckBar` with a one-time UserDefaults migration from the old domain. Brand: notch-as-pocket, tuck/untuck voice woven into the app UI.
- **2026-05-29** — **Snooze over cycle**: temporary one-shot reveal that auto-re-tucks (not a repeating duty cycle).
- **2026-05-29** — **Normal vs Protected** model replaced the live "Right now" override + conflict banner; the app just switches modes by display. Dock is protected-only with snapshot/restore.
- **2026-05-29** — Dock now driven through **System Events** (no `killall Dock`) → no desktop flash.
- **2026-05-28** — Build **both**, sequenced: solidify *tuck* first, then *dim* (DDC + overlay) as the marquee feature.
- **2026-05-28** — Live menu-bar apply uses System Events, matching Leland's proven `~/toggle-menu-bar.zsh`. SkyLight `SLSSetMenuBarAutohideEnabled` set the flag but didn't visibly apply, so it was dropped.

## Open questions
- DDC/CI reliability on the AW3225QF over its current connection (DP vs HDMI)?
- Which icon motion becomes the static icon — the mid-tuck "Bulge → Tuck" frame is the current pick.
