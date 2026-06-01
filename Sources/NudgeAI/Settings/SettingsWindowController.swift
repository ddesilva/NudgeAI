import AppKit
import SwiftUI

/// Hosts `SettingsView` in a small floating window. A single shared instance is
/// reused so repeated "Settings…" just brings it forward.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "Nudge AI — Settings"
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.setContentSize(NSSize(width: 460, height: 340))
        win.center()
        win.isReleasedWhenClosed = false

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
