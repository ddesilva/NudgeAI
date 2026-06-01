import AppKit
import SwiftUI

/// Hosts `ReviewView` in a standard window and wires up export.
@MainActor
final class ReviewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var session: SessionController?

    init(session: SessionController) {
        self.session = session
        super.init()
    }

    func show() {
        guard let session else { return }

        let root = ReviewView(
            session: session,
            onExport: { [weak self] in self?.export() },
            onClose: { [weak self] in self?.close() }
        )

        let hosting = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Nudge AI — Review"
        win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        win.setContentSize(NSSize(width: 640, height: 560))
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func export() {
        guard let session else { return }
        do {
            let result = try Exporter.export(annotations: session.annotations)
            Exporter.copyPromptToClipboard(result.promptForAgent)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    func close() {
        window?.close()
        window = nil
        session?.closeReview()
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            window = nil
            session?.closeReview()
        }
    }
}
