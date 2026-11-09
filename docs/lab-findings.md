# Lab findings: issue #1 (windows in the tucked strip)

Measured 2026-11-03 on GitHub-hosted runners: macOS 15.8 (`macos-15`), macOS 26 (`macos-26`), macOS 27.0.1
(`xcode-27`). 1024×768 screen, no notch; a second display is a `CGVirtualDisplay` (1440×900). The shell has
Accessibility, Apple Events and Screen Recording granted. Workflow: `.github/workflows/lab.yml`; code:
`Lab/Sources/Lab/main.swift` (run one experiment with the workflow's `which` input). Unless noted, all three OS
versions behaved the same.

## Answers

| Question | Answer | Experiment |
| --- | --- | --- |
| Can a window be moved into the strip while the real bar is showing? | **No.** The target app's AppKit clamps it below the bar (y=25 on 15, y=31 on 26/27), whether moved by AX, `setFrame`, or a drag. The window server itself allows it: a window that overrides `constrainFrameRect` sits at y=0. | `ax`, `own`, `drag` |
| Is that clamp per display? | **Yes.** On the second display a window is clamped to that display's bar. | `multi` |
| Is native auto-hide per display? | **No.** Turning it on frees the strip on every display (`topInset` 0 on both). | `multi` |
| Does native auto-hide let windows use the strip? | **Yes**, on every display (height still capped by the Dock). | `ax`, `multi` |
| Is the native hover reveal slow? | **Not on these runners.** The bar starts sliding in 14–96 ms after the pointer reaches the top edge and is fully in by ~150–190 ms. | `reveal` |
| Would TuckBar flipping auto-hide be a faster reveal? | **No.** The in-process System Events call alone takes 130–140 ms; first visible change ~155 ms (180–250 ms via `osascript`). | `reveal` |
| Do windows move when auto-hide changes? | A window the **user dragged** stays put. Windows placed **programmatically** (AX or `setFrame`) snapped back to their creation frame after a flip, on macOS 27. So flipping auto-hide at runtime can scramble layouts. | `toggle2`, `drag`, `ownstrip` |
| macOS 27: does v0.1's apply order (System Events, then restart SystemUIServer) undo the hide? (#2) | **Not reproduced** on 27.0.1. Both orders leave the bar hidden. PR #7 keeps the reordered path for 27 because it is equally correct and makes one fewer process restart. | `order` |
| Does the cover still sit above the macOS 27 menu bar? (#4) | **Yes.** The 27 bar is one `Window Server` "Menubar" window per display at layer 24 (plus an offscreen `MenuBarAgent` window). The cover is at 25. On 15 the hidden bar moves to y=−24; on 27 it stays at y=0 and is drawn transparent. | `env` |
| macOS 27: why is the wallpaper cover black with Screen Recording granted? | The per-display "Wallpaper" window moved from the **Dock** to **WindowManager** (layer −2147483624, measured on 27.2). The capture matched on the Dock's bundle ID, found nothing and fell back to black (mean RGB 0,0,0). Fixed by matching title + layer + coverage, and by capturing the composited desktop by default. Seam after the fix: 0.36 luma. | dev Mac, 27.2 |
| macOS 27: how fast is the cover's reveal now? | Driven by mouse-move events: fading by 20 ms, gone by 115 ms. Re-tuck: 0.7 s linger, then a 0.45 s eased fade. | dev Mac, 27.2 |
| macOS 27: can the native auto-hide reveal be made faster? | **No setting found.** The reveal moved into `MenuBarAgent` (`com.apple.menubar:reveal`); its binary has no dwell or delay key, and its defaults domain holds only analytics. Third-party reports put the dwell at 75–380 ms. | dev Mac, 27.2 |

## Decisions

1. **Per-display "windows in the strip, bar still visible on the other display" is not possible** with public
   API. Each app keeps its own windows out of a visible bar's strip, and only the global auto-hide frees it.
2. **Ship "Use the full screen" (#5).** With several displays, TuckBar uses native auto-hide instead of the cover
   while a tagged display is connected. Windows can use the strip on the tagged display; the cost is that the
   bar also auto-hides on the other display. Verified end to end by `scripts/e2e.sh` on 15, 26 and 27.
3. **Don't ship a pointer-driven mode** (auto-hide on while the pointer is on the tagged display, off elsewhere).
   It isn't faster than the native reveal, and each flip can move programmatically placed windows.
4. **The "slow reveal" complaint does not reproduce** on CI. On a real Mac it may come from something the runners
   lack (a notch, the external display's arrangement, a trackpad's motion). Needs one measurement on hardware
   like the customer's before anything is built for it.

## Limits of this evidence

- Virtual screens have no notch; the customer's MacBook Pro does. Check full-screen mode on a notched display.
- No Dynamic Island hardware (2026 OLED MacBook Pro). Whether the island draws above the cover's level 25 is unknown; the cover leaves the housing gap open either way.
- Synthetic mouse events: two of three title-bar drags did not move the window (cause not found), so the
  "user-dragged window stays put" result rests on one drag per OS.
- Reveal timing uses `CGEvent` mouse moves, not a physical pointer.
