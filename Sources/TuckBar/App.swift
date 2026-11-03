import AppKit
import SwiftUI

@main
struct TuckBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            Image(nsImage: model.statusGlyph)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var sigterm: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `kill` / `killall TuckBar` sends SIGTERM, which would exit without
        // applicationWillTerminate and leave the menu bar hidden until the next launch.
        // Route it through a normal terminate so the bar and Dock are restored.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigterm = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.restoreForQuit()
    }
}
