import AppKit
import SwiftUI

/// Hosting view that always accepts the first mouse click. The HUD lives in
/// a non-activating panel that sits over the (key) selection overlay, so
/// without this the very first click on Done/Cancel/Box gets swallowed by
/// AppKit's "click to focus" path and the button never fires.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A persistent, always-on-top session HUD shown for the whole session.
/// Sits ABOVE the selection overlay so Done/Cancel are always clickable.
@MainActor
final class FloatingControlController {
    private var panel: NSPanel?
    private let model = HUDModel()

    var onAddBox: (@MainActor () -> Void)?
    var onDone: (@MainActor () -> Void)?
    var onCancel: (@MainActor () -> Void)?

    /// One step above the instruction panel and overlay so it's always on top.
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)

    func show(count: Int) {
        model.count = count
        guard panel == nil else { return }

        let root = SessionHUDView(
            model: model,
            onAddBox: { [weak self] in self?.onAddBox?() },
            onDone: { [weak self] in self?.onDone?() },
            onCancel: { [weak self] in self?.onCancel?() }
        )

        let hosting = FirstMouseHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Self.level
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel

        // Bottom-center of the main screen's visible area (clear of the menu bar).
        if let visible = NSScreen.main?.visibleFrame {
            let x = visible.midX - size.width / 2
            let y = visible.minY + 28
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
    }

    func updateCount(_ count: Int) {
        model.count = count
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
