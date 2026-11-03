# Lab findings: issue #1 (windows in the tucked strip)

Measured on GitHub-hosted runners: macOS 15.8 (`macos-15`), macOS 26 (`macos-26`), macOS 27.0.1
(`xcode-27`). 1024×768 virtual screen, no notch. The shell has Accessibility, Apple Events and
Screen Recording granted. Workflow: `.github/workflows/lab.yml`, code: `Lab/Sources/Lab/main.swift`.

## Answers

| Question | Answer | Evidence |
| --- | --- | --- |
| Can a window be moved into the strip while the real bar is showing? | **No**, on every OS. AppKit in the *target app* clamps it below the bar (y=25 on 15, y=31 on 27). The window server itself allows it (a window that overrides `constrainFrameRect` sits at y=0). | `ax.move`, `own.window` |
| Is the clamp per display? | **Yes.** With two displays, a window on the second display is clamped to *that* display's bar. | `multi.ax` (virtual display) |
| Is native auto-hide per display? | **No.** Turning it on frees the strip on every display. | `multi.on` (both `topInset` 0) |
| Does native auto-hide let windows use the strip? | **Yes.** With auto-hide on, AX and drags place windows at y=0 (height capped by the Dock). | `ax.move` autohide=true |
| Is the native hover reveal slow? | **Not on these runners.** The bar starts sliding in 14–96 ms after the pointer reaches the top and is fully in by ~150–190 ms. | `reveal` (pixel diff of the strip) |
| Is TuckBar flipping auto-hide via System Events faster? | **No.** ~130–140 ms for the in-process AppleScript call alone; first visible change ~155 ms; ~180–250 ms via `osascript`. | `reveal` |
| On macOS 27, does v0.1's apply order (System Events, then restart SystemUIServer) undo the hide? (#2) | **Not reproduced** on 27.0.1. Both orders leave the bar hidden. | `order.old` / `order.new` |
| Does the cover still sit above the macOS 27 menu bar? (#4) | **Yes.** The 27 menu bar is one `Window Server` "Menubar" window at layer 24 (plus an offscreen `MenuBarAgent` window); the cover is at 25. | `env.start.chrome` |
| Do windows jump when auto-hide changes? | AX-placed windows snap back to the frame AppKit last knew (an AX artifact). A window the user dragged stays put. | `toggle2`, `drag` |

## What this means for the customer

- **Per-display "windows in the strip" with the bar still showing on the other display is not
  possible** with public API. Each app keeps its own windows out of a visible bar's strip.
- The only switch that frees the strip is native auto-hide, and it is global. That is what
  "Use the full screen" (#5) does with several displays.
- The "slow reveal" complaint does not reproduce on CI hardware. On a real Mac it may come from
  something the runners don't have (a notch, an external display arrangement, a trackpad). Needs
  a measurement on the customer's kind of machine.
