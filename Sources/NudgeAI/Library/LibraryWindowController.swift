import AppKit
import SwiftUI

/// Hosts the `LibraryView` in a standard window. A single shared instance is
/// reused so repeated "Browse Sessions" just brings it forward.
@MainActor
final class LibraryWindowController {
    static let shared = LibraryWindowController()
    private var window: NSWindow?

    func show(selectingFolder folder: URL? = nil) {
        if window == nil {
            let root = LibraryView(
                onSendTo: { [weak self] prompt in
                    // Send-to picker removed in v0.3 — drop straight to clipboard.
                    Exporter.copyPromptToClipboard(prompt)
                    self?.close()
                }
            )
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Nudge AI — Sessions"
            // .fullSizeContentView + transparent titlebar lets the sidebar
            // glass extend all the way up under the traffic lights, matching
            // modern Finder. Title text is hidden so the strip stays clean.
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.setContentSize(NSSize(width: 1100, height: 600))
            win.center()
            win.isReleasedWhenClosed = false
            self.window = win
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Hand the target down to LibraryView via notification so the same
        // entry point works whether the window was just created or was
        // already on screen with stale selection. Posted on the next run
        // loop tick so a fresh window's onAppear has a chance to wire up
        // the publisher before the notification fires.
        if let folder {
            let path = folder.path
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .nudgeSelectSession,
                    object: nil,
                    userInfo: ["folder": path]
                )
            }
        }
    }

    func close() {
        window?.orderOut(nil)
    }
}
