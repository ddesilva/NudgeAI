import AppKit

/// Borderless windows return `false` from `canBecomeKey` by default, which
/// means `keyDown` never reaches the content view — so Escape silently
/// no-ops. Subclassing lets the overlay accept key events.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns one borderless transparent window PER connected display, each hosting
/// a `SelectionView`. macOS's "Displays have separate Spaces" setting clips a
/// single multi-screen-spanning window to one display, so we have to put one
/// window on each screen instead. The shared selection state (start point,
/// current rect) lives here so a drag that begins on one display and ends on
/// another is tracked as one continuous selection.
@MainActor
final class SelectionOverlayController {
    private var windows: [NSWindow] = []
    private var views: [SelectionView] = []

    var onSelect: (@MainActor (NSRect) -> Void)?
    var onCancel: (@MainActor () -> Void)?

    /// Drag state, in global AppKit coordinates. `nil` between drags.
    var startPoint: NSPoint?
    var currentRect: NSRect?

    func show() {
        close()

        for (i, screen) in NSScreen.screens.enumerated() {
            let win = OverlayWindow(
                contentRect: screen.frame,
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
            win.setFrame(screen.frame, display: true)

            let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.windowGlobalOrigin = screen.frame.origin
            view.controller = self
            win.contentView = view

            windows.append(win)
            views.append(view)

            if i == 0 {
                // First window gets key status so it receives keyDown (Esc).
                NSApp.activate(ignoringOtherApps: true)
                win.makeKeyAndOrderFront(nil)
                win.makeFirstResponder(view)
            } else {
                win.orderFrontRegardless()
            }
        }
    }

    func close() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        startPoint = nil
        currentRect = nil
    }

    var isVisible: Bool { !windows.isEmpty }

    // MARK: Called by SelectionView in response to mouse events.

    func beginDrag(at global: NSPoint) {
        startPoint = global
        currentRect = NSRect(origin: global, size: .zero)
        redrawAll()
    }

    func updateDrag(to global: NSPoint) {
        guard let start = startPoint else { return }
        currentRect = NSRect(
            x: min(start.x, global.x),
            y: min(start.y, global.y),
            width: abs(global.x - start.x),
            height: abs(global.y - start.y)
        )
        redrawAll()
    }

    func endDrag() {
        defer {
            startPoint = nil
            currentRect = nil
            redrawAll()
        }
        guard let rect = currentRect, rect.width >= 3, rect.height >= 3 else { return }
        let cb = onSelect
        close()
        cb?(rect)
    }

    func cancelDrag() {
        let cb = onCancel
        close()
        cb?()
    }

    private func redrawAll() {
        for v in views { v.needsDisplay = true }
    }
}

// Internal access for SelectionView so it can read drag state during draw.
extension SelectionOverlayController {
    var currentSelectionRect: NSRect? { currentRect }
}
