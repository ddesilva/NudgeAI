import AppKit
import SwiftUI

/// Hosts `ReviewView` in a standard window and wires up export.
@MainActor
final class ReviewWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var session: SessionController?
    private var picker: SendToPickerController?

    init(session: SessionController) {
        self.session = session
        super.init()
    }

    func show() {
        guard let session else { return }

        let root = ReviewView(
            session: session,
            onExport: { [weak self] in self?.export() },
            onSendTo: { [weak self] in self?.showSendPicker() },
            onClose: { [weak self] in self?.close() },
            developerModeEnabled: Preferences.developerModeEnabled
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

    private func showSendPicker() {
        guard let session else { return }
        let result: Exporter.Result
        do {
            result = try Exporter.export(annotations: session.annotations)
        } catch {
            NSAlert(error: error).runModal()
            return
        }

        let controller = SendToPickerController()
        self.picker = controller
        controller.present(host: window) { [weak self] target in
            self?.picker = nil
            guard let target else { return }
            _ = SendDispatcher.send(prompt: result.promptForAgent, to: target)
            // Close Review after a successful send so the target window comes
            // to the front unobstructed.
            self?.close()
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
