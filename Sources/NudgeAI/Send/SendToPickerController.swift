import AppKit
import SwiftUI

/// Presents `SendToPickerView` as a modal sheet on a host window, or as a
/// standalone panel when no host window is available (e.g. the floating
/// instruction panel during a capture session).
@MainActor
final class SendToPickerController: NSObject, NSWindowDelegate {
    private var sheet: NSWindow?
    private weak var host: NSWindow?
    private var onResult: ((SendDispatcher.Target?) -> Void)?

    /// `host` is the window the sheet will attach to. Pass `nil` for a floating
    /// panel (used by the instruction panel which is borderless).
    func present(host: NSWindow?, onResult: @escaping (SendDispatcher.Target?) -> Void) {
        guard sheet == nil else { return }
        self.host = host
        self.onResult = onResult

        let view = SendToPickerView(
            onPick: { [weak self] target in self?.finish(with: target) },
            onCancel: { [weak self] in self?.finish(with: nil) }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "Send to"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 520, height: 480))
        window.delegate = self

        self.sheet = window

        if let host {
            host.beginSheet(window)
        } else {
            window.center()
            // Keep this at .normal — `.floating` sits above the system TCC
            // permission prompt (the "Nudge AI wants to control iTerm"
            // dialog), making it impossible to click Allow on first launch.
            window.level = .normal
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func finish(with target: SendDispatcher.Target?) {
        let callback = onResult
        onResult = nil

        if let window = sheet {
            if let host {
                host.endSheet(window)
            }
            window.orderOut(nil)
        }
        sheet = nil
        host = nil

        callback?(target)
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Window closed by the system (e.g. user hit the red traffic light).
            // Treat as cancel if we haven't already resolved.
            finish(with: nil)
        }
    }
}
