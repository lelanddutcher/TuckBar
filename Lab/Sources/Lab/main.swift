// TuckBar Lab: probes for issue #1 on a real macOS GUI session (GitHub-hosted runner).
//
//   Lab all            run every experiment, print `LAB <tag> <json>` lines
//   Lab window TITLE   helper: a regular app with one titled window (an AX target)
//
// Every experiment restores the menu-bar auto-hide state it found.

import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

// MARK: - Output

func emit(_ tag: String, _ obj: Any) {
    let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data("\"<unserializable>\"".utf8)
    print("LAB \(tag) \(String(decoding: data, as: UTF8.self))")
    fflush(stdout)
}

func spin(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

func r(_ x: CGFloat) -> Double { (Double(x) * 10).rounded() / 10 }
func rect(_ f: CGRect) -> [String: Double] { ["x": r(f.minX), "y": r(f.minY), "w": r(f.width), "h": r(f.height)] }

// MARK: - Subprocesses (always bounded: TCC prompts must never hang the job)

struct ShResult { var code: Int32; var out: String; var err: String; var timedOut: Bool
    var dict: [String: Any] { ["code": Int(code), "out": out, "err": err, "timedOut": timedOut] } }

@discardableResult
func sh(_ path: String, _ args: [String], timeout: Double = 15) -> ShResult {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let o = Pipe(), e = Pipe()
    p.standardOutput = o; p.standardError = e
    do { try p.run() } catch { return ShResult(code: -1, out: "", err: "\(error)", timedOut: false) }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { spin(0.05) }
    var timedOut = false
    if p.isRunning { timedOut = true; p.terminate(); spin(0.3) }
    let out = String(decoding: o.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let err = String(decoding: e.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return ShResult(code: p.isRunning ? -2 : p.terminationStatus,
                    out: out.trimmingCharacters(in: .whitespacesAndNewlines),
                    err: err.trimmingCharacters(in: .whitespacesAndNewlines), timedOut: timedOut)
}

func osa(_ src: String, timeout: Double = 15) -> ShResult { sh("/usr/bin/osascript", ["-e", src], timeout: timeout) }

// MARK: - State snapshots

func screens() -> [[String: Any]] {
    NSScreen.screens.map { s in
        var d: [String: Any] = [
            "id": (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? -1,
            "frame": rect(s.frame), "visible": rect(s.visibleFrame),
            "topInset": r(s.frame.maxY - s.visibleFrame.maxY), "scale": Double(s.backingScaleFactor),
        ]
        if #available(macOS 12.0, *) {
            d["safeTop"] = r(s.safeAreaInsets.top)
            d["hasNotch"] = s.auxiliaryTopLeftArea != nil
        }
        return d
    }
}

/// Windows that look like menu-bar chrome: anything at the very top, short, above normal level.
func topChromeWindows() -> [[String: Any]] {
    guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { w in
        let layer = w[kCGWindowLayer as String] as? Int ?? 0
        guard let b = w[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        let name = w[kCGWindowName as String] as? String ?? ""
        let isTop = bounds.minY <= 1 && bounds.height <= 60 && bounds.width >= 200
        guard layer > 0, isTop || name.localizedCaseInsensitiveContains("menu") else { return nil }
        return ["layer": layer, "owner": owner, "name": name, "bounds": rect(bounds),
                "onscreen": w[kCGWindowIsOnscreen as String] as? Bool ?? false,
                "alpha": w[kCGWindowAlpha as String] as? Double ?? -1]
    }
}

func autohideState() -> [String: Any] {
    let se = osa("tell application \"System Events\" to get autohide menu bar of dock preferences")
    let d1 = sh("/usr/bin/defaults", ["read", "NSGlobalDomain", "_HIHideMenuBar"])
    let d2 = sh("/usr/bin/defaults", ["read", "NSGlobalDomain", "AppleMenuBarVisibleInFullscreen"])
    return ["systemEvents": se.code == 0 ? se.out : "ERR \(se.code) \(se.err)\(se.timedOut ? " (timeout)" : "")",
            "_HIHideMenuBar": d1.code == 0 ? d1.out : "unset",
            "VisibleInFullscreen": d2.code == 0 ? d2.out : "unset"]
}

func snapshot(_ label: String) -> [String: Any] {
    let main = NSScreen.screens.first
    return ["label": label,
            "barReserved": main.map { $0.frame.maxY - $0.visibleFrame.maxY > 1 } ?? false,
            "topInset": main.map { r($0.frame.maxY - $0.visibleFrame.maxY) } ?? -1,
            "autohide": autohideState(),
            "chrome": topChromeWindows()]
}

// MARK: - Applying auto-hide (mirrors SystemSettings.setMenuBarVisibility)

@discardableResult
func seSet(_ hide: Bool) -> ShResult {
    osa("tell application \"System Events\" to set autohide menu bar of dock preferences to \(hide)")
}
func writeDefaults(_ hide: Bool) {
    sh("/usr/bin/defaults", ["write", "NSGlobalDomain", "_HIHideMenuBar", "-bool", hide ? "true" : "false"])
    sh("/usr/bin/defaults", ["write", "NSGlobalDomain", "AppleMenuBarVisibleInFullscreen", "-bool", hide ? "false" : "true"])
}
func restartAgents() {
    sh("/usr/bin/killall", ["ControlCenter"]); sh("/usr/bin/killall", ["SystemUIServer"])
}

/// v0.1 order (TuckBar <= PR #7 on every OS): System Events, defaults, restart agents.
func applyOld(_ hide: Bool) -> [String: Any] { let se = seSet(hide); writeDefaults(hide); restartAgents(); return se.dict }
/// PR #7 order for macOS 27+: defaults, then System Events last, no restart.
func applyNew(_ hide: Bool) -> [String: Any] { writeDefaults(hide); return seSet(hide).dict }

func restoreVisible() {
    writeDefaults(false); seSet(false); spin(2.5)
}


// MARK: - Pixels: capture the top strip and diff it (detects the bar appearing)

var scDisplay: SCDisplay?

func captureStrip(height: Int = 40) -> CGImage? {
    var result: CGImage?
    var done = false
    Task {
        do {
            if scDisplay == nil {
                scDisplay = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true).displays.first
            }
            if let d = scDisplay {
                let cfg = SCStreamConfiguration()
                cfg.sourceRect = CGRect(x: 0, y: 0, width: d.width, height: height)
                cfg.width = d.width
                cfg.height = height
                cfg.showsCursor = false
                result = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: d, excludingWindows: []),
                                                                    configuration: cfg)
            }
        } catch { print("capture error: \(error)") }
        done = true
    }
    let deadline = Date().addingTimeInterval(2)
    while !done && Date() < deadline { spin(0.002) }
    return result
}

func rgba(_ img: CGImage) -> [UInt8] {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { p in
        let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return buf
}

/// Mean absolute per-channel difference, 0...255.
func diff(_ a: [UInt8], _ b: [UInt8]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var sum = 0
    for i in stride(from: 0, to: a.count, by: 4) {
        sum += abs(Int(a[i]) - Int(b[i])) + abs(Int(a[i+1]) - Int(b[i+1])) + abs(Int(a[i+2]) - Int(b[i+2]))
    }
    return (Double(sum) / Double(a.count / 4 * 3) * 100).rounded() / 100
}

// MARK: - Pointer

func moveMouse(to p: CGPoint) {
    CGWarpMouseCursorPosition(p)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

/// Glide to `p` in a few real mouse-moved events (the system's hover tracking wants motion, not a warp).
func glide(to p: CGPoint, from q: CGPoint) {
    for i in 1...6 {
        let t = CGFloat(i) / 6
        let pt = CGPoint(x: q.x + (p.x - q.x) * t, y: q.y + (p.y - q.y) * t)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
        spin(0.015)
    }
}

/// Sample the strip for `seconds`, return [[ms, diff]] against `base` and the first ms over `threshold`.
func watchStrip(base: [UInt8], seconds: Double, threshold: Double = 4, from t0: Date) -> (series: [[Double]], first: Double?) {
    var series: [[Double]] = []
    var first: Double?
    let end = Date().addingTimeInterval(seconds)
    while Date() < end {
        guard let img = captureStrip() else { spin(0.02); continue }
        let ms = (Date().timeIntervalSince(t0) * 1000).rounded()
        let d = diff(base, rgba(img))
        series.append([ms, d])
        if first == nil && d > threshold { first = ms }
    }
    return (series, first)
}

// In-process System Events (what the app does), compiled once.
let seOn = NSAppleScript(source: "tell application \"System Events\" to set autohide menu bar of dock preferences to true")!
let seOff = NSAppleScript(source: "tell application \"System Events\" to set autohide menu bar of dock preferences to false")!
func seInProcess(_ hide: Bool) -> [String: Any] {
    var err: NSDictionary?
    let t0 = Date()
    (hide ? seOn : seOff).executeAndReturnError(&err)
    return ["ms": (Date().timeIntervalSince(t0) * 1000).rounded(), "error": err.map { "\($0)" } ?? ""]
}

// MARK: - Experiments

func expEnvironment() {
    var d: [String: Any] = [
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "axTrusted": AXIsProcessTrusted(),
        "screenCapture": CGPreflightScreenCaptureAccess(),
        "statusBarThickness": Double(NSStatusBar.system.thickness),
        "levels": ["mainMenu": Int(CGWindowLevelForKey(.mainMenuWindow)),
                   "status": Int(CGWindowLevelForKey(.statusWindow)),
                   "popUpMenu": Int(CGWindowLevelForKey(.popUpMenuWindow)),
                   "normal": Int(CGWindowLevelForKey(.normalWindow))],
        "screens": screens(),
    ]
    d["start"] = snapshot("start")
    emit("env", d)
}

/// #2: does the v0.1 order (agent restart after System Events) undo the hide? Compare with PR #7's order.
func expApplyOrder() {
    restoreVisible()
    emit("order.baseline", snapshot("baseline"))
    for (name, apply) in [("old", applyOld), ("new", applyNew)] as [(String, (Bool) -> [String: Any])] {
        let res = apply(true)
        var samples: [[String: Any]] = []
        var t = 0.0
        for at in [0.5, 1.5, 3.0, 6.0] { spin(at - t); t = at; samples.append(snapshot("\(name)+\(at)s")) }
        emit("order.\(name)", ["seResult": res, "samples": samples])
        restoreVisible()
        emit("order.\(name).restored", snapshot("restored"))
    }
}

// AX helpers
func axApp(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }
func axWindows(_ app: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success else { return [] }
    return v as? [AXUIElement] ?? []
}
func axFrame(_ w: AXUIElement) -> [String: Double]? {
    var pv: CFTypeRef?, sv: CFTypeRef?
    guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &pv) == .success,
          AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sv) == .success else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(pv as! AXValue, .cgPoint, &p); AXValueGetValue(sv as! AXValue, .cgSize, &s)
    return rect(CGRect(origin: p, size: s))
}
func axSet(_ w: AXUIElement, origin: CGPoint, size: CGSize) -> [String: Any] {
    var p = origin, s = size
    let e1 = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    let e2 = AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!)
    // Position again: a resize can nudge it.
    let e3 = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    return ["posErr": Int(e1.rawValue), "sizeErr": Int(e2.rawValue), "pos2Err": Int(e3.rawValue)]
}

/// CGWindowList bounds (top-left origin) of every on-screen window owned by `pid`.
func cgBounds(pid: pid_t) -> [[String: Double]] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { w in
        guard (w[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == pid,
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let f = CGRect(dictionaryRepresentation: b as CFDictionary) else { return nil }
        return rect(f)
    }
}

/// #6: can a window be moved into the menu-bar strip with AX (bar visible vs auto-hidden)?
func expAXMove() {
    guard AXIsProcessTrusted() else { emit("ax.skip", ["reason": "process not AX-trusted"]); return }
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
    let helper = Process()
    helper.executableURL = URL(fileURLWithPath: exe)
    helper.arguments = ["window", "LabTarget"]
    do { try helper.run() } catch { emit("ax.skip", ["reason": "helper launch failed: \(error)"]); return }
    defer { helper.terminate() }

    var targets: [(String, pid_t)] = [("helper", helper.processIdentifier)]
    // A real third-party app too, best effort.
    sh("/usr/bin/open", ["-a", "TextEdit"])
    _ = osa("tell application \"TextEdit\" to make new document", timeout: 20)
    spin(2)
    if let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
        targets.append(("TextEdit", te.processIdentifier))
    }

    let screenH = NSScreen.screens.first.map { $0.frame.height } ?? 800
    for hidden in [false, true] {
        if hidden { _ = applyNew(true); spin(3) } else { restoreVisible() }
        let state = snapshot(hidden ? "autohide-on" : "autohide-off")
        var results: [[String: Any]] = []
        for (name, pid) in targets {
            let app = axApp(pid)
            var wins: [AXUIElement] = []
            for _ in 0..<40 { wins = axWindows(app); if !wins.isEmpty { break }; spin(0.25) }
            guard let w = wins.first else { results.append(["target": name, "error": "no AX window"]); continue }
            let before = axFrame(w)
            // Ask for the top-left corner of the main screen, full height: the "use the strip" layout.
            let errs = axSet(w, origin: CGPoint(x: 0, y: 0), size: CGSize(width: 640, height: screenH))
            spin(1)
            results.append(["target": name, "before": before ?? [:], "asked": rect(CGRect(x: 0, y: 0, width: 640, height: screenH)),
                            "after": axFrame(w) ?? [:], "cg": cgBounds(pid: pid), "errors": errs])
        }
        emit("ax.move", ["autohide": hidden, "topInset": state["topInset"] ?? -1, "results": results])
    }
    restoreVisible()
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first?.terminate()
}

/// Own window, in-process: does AppKit or the window server keep a window out of the strip?
func expOwnWindow() {
    guard let screen = NSScreen.screens.first else { return }
    final class Unconstrained: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    }
    let full = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 640, height: screen.frame.height)
    var out: [[String: Any]] = []
    for (name, win) in [("NSWindow", NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)),
                        ("unconstrained", Unconstrained(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
                                                        styleMask: [.titled, .resizable], backing: .buffered, defer: false))] {
        win.title = name
        win.orderFrontRegardless()
        win.setFrame(full, display: true)
        spin(0.7)
        out.append(["window": name, "asked": rect(full), "frame": rect(win.frame),
                    "cg": cgBounds(pid: getpid())])
        win.orderOut(nil)
    }
    emit("own.window", ["topInset": r(screen.frame.maxY - screen.visibleFrame.maxY), "results": out])
}


/// How fast does the bar appear: native hover reveal vs TuckBar flipping auto-hide off?
func expReveal() {
    guard let screen = NSScreen.screens.first else { return }
    let f = screen.frame
    let center = CGPoint(x: f.midX, y: f.midY)          // CG global coords: top-left origin
    let top = CGPoint(x: f.midX, y: 0)
    guard captureStrip() != nil else { emit("reveal.skip", ["reason": "no screen capture"]); return }
    // Warm up the in-process AppleScript (first call compiles/launches System Events).
    _ = seInProcess(false); spin(1.5)

    for round in 1...3 {
        // Native: auto-hide on, pointer away, then glide to the top edge.
        _ = applyNew(true); moveMouse(to: center); spin(2.5)
        guard let baseImg = captureStrip() else { continue }
        let base = rgba(baseImg)
        glide(to: top, from: center)
        let t0 = Date()
        let native = watchStrip(base: base, seconds: 3, from: t0)
        let chromeAtEnd = topChromeWindows()
        moveMouse(to: center); spin(2.5)

        // TuckBar-driven: pointer away, call System Events (in-process) to turn auto-hide off.
        guard let baseImg2 = captureStrip() else { continue }
        let base2 = rgba(baseImg2)
        let t1 = Date()
        let call = seInProcess(false)
        let driven = watchStrip(base: base2, seconds: 2, from: t1)
        _ = seInProcess(true); spin(1.5)

        // TuckBar-driven via osascript subprocess, for comparison.
        guard let baseImg3 = captureStrip() else { continue }
        let base3 = rgba(baseImg3)
        let t2 = Date()
        let callOsa = seSet(false)
        let callOsaMs = (Date().timeIntervalSince(t2) * 1000).rounded()
        let drivenOsa = watchStrip(base: base3, seconds: 2, from: t2)
        _ = seInProcess(true); spin(1.5)

        emit("reveal", ["round": round,
                        "nativeFirstMs": native.first ?? -1, "native": native.series,
                        "nativeChromeAtEnd": chromeAtEnd,
                        "seCall": call, "drivenFirstMs": driven.first ?? -1, "driven": driven.series,
                        "osaCallMs": callOsaMs, "osaCode": Int(callOsa.code),
                        "drivenOsaFirstMs": drivenOsa.first ?? -1])
    }
    restoreVisible()
}

/// When auto-hide turns off, are windows sitting in the strip pushed down (or left under the bar)?
func expToggleWindows() {
    guard AXIsProcessTrusted() else { emit("toggle.skip", ["reason": "not AX-trusted"]); return }
    sh("/usr/bin/open", ["-a", "TextEdit"])
    _ = osa("tell application \"TextEdit\" to make new document", timeout: 20)
    spin(2)
    guard let te = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first else {
        emit("toggle.skip", ["reason": "no TextEdit"]); return
    }
    let app = axApp(te.processIdentifier)
    var wins: [AXUIElement] = []
    for _ in 0..<40 { wins = axWindows(app); if !wins.isEmpty { break }; spin(0.25) }
    guard let w = wins.first else { emit("toggle.skip", ["reason": "no AX window"]); return }
    let screenH = NSScreen.screens.first.map { $0.frame.height } ?? 768

    _ = applyNew(true); spin(3)
    _ = axSet(w, origin: .zero, size: CGSize(width: 640, height: screenH)); spin(1)
    var samples: [[String: Any]] = [["label": "autohide-on, placed", "frame": axFrame(w) ?? [:]]]
    _ = seInProcess(false)
    for at in [0.3, 1.0, 3.0] { spin(at == 0.3 ? 0.3 : at == 1.0 ? 0.7 : 2.0)
        samples.append(["label": "off+\(at)s", "frame": axFrame(w) ?? [:], "topInset": snapshot("x")["topInset"] ?? -1]) }
    _ = seInProcess(true)
    for at in [0.3, 1.0, 3.0] { spin(at == 0.3 ? 0.3 : at == 1.0 ? 0.7 : 2.0)
        samples.append(["label": "on-again+\(at)s", "frame": axFrame(w) ?? [:], "topInset": snapshot("x")["topInset"] ?? -1]) }
    // Does the app re-constrain the window when it is next activated / resized slightly?
    te.activate(options: [])
    spin(1)
    samples.append(["label": "after activate", "frame": axFrame(w) ?? [:]])
    emit("toggle.windows", ["samples": samples])
    restoreVisible()
    te.terminate()
}

// MARK: - Entry

let args = CommandLine.arguments
let app = NSApplication.shared

if args.count >= 2 && args[1] == "window" {
    app.setActivationPolicy(.regular)
    let w = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 500, height: 320),
                     styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
    w.title = args.count >= 3 ? args[2] : "LabTarget"
    w.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}

app.setActivationPolicy(.accessory)
app.finishLaunching()
spin(0.5)

let which = args.count >= 2 ? args[1] : "all"
let found = autohideState()
emit("begin", ["which": which, "found": found])

if which == "all" || which == "env" { expEnvironment() }
if which == "all" || which == "order" { expApplyOrder() }
if which == "all" || which == "own" { expOwnWindow() }
if which == "all" || which == "ax" { expAXMove() }
if which == "all" || which == "reveal" { expReveal() }
if which == "all" || which == "toggle" { expToggleWindows() }

restoreVisible()
emit("end", snapshot("end"))
exit(0)
