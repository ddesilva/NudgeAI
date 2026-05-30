import AppKit

/// Owns a borderless transparent window that covers every display and hosts
/// a `SelectionView` for dragging out a region.
@MainActor
final class SelectionOverlayController {
    private var window: NSWindow?

    var onSelect: (@MainActor (NSRect) -> Void)?
    var onCancel: (@MainActor () -> Void)?

    /// Union of all screen frames in AppKit global coordinates.
    private static func globalBounds() -> NSRect {
        NSScreen.screens.reduce(NSRect.zero) { $0.union($1.frame) }
    }

    func show() {
        let frame = Self.globalBounds()

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.ignoresMouseEvents = false
        win.hasShadow = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.setFrame(frame, display: true)

        let view = SelectionView(frame: NSRect(origin: .zero, size: frame.size))
        view.windowGlobalOrigin = frame.origin
        view.onSelect = { [weak self] rect in
            self?.close()
            self?.onSelect?(rect)
        }
        view.onCancel = { [weak self] in
            self?.close()
            self?.onCancel?()
        }
        win.contentView = view

        self.window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(view)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }

    var isVisible: Bool { window != nil }
}
