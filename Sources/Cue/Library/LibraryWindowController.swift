import AppKit
import SwiftUI

/// Hosts the `LibraryView` in a standard window. A single shared instance is
/// reused so repeated "Browse Sessions" just brings it forward.
@MainActor
final class LibraryWindowController {
    static let shared = LibraryWindowController()
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: LibraryView())
        let win = NSWindow(contentViewController: hosting)
        win.title = "Cue — Sessions"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 900, height: 600))
        win.center()
        win.isReleasedWhenClosed = false

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}
