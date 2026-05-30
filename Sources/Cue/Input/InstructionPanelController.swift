import AppKit
import SwiftUI

/// Hosts the sleek SwiftUI `InstructionPanelView` in a borderless key panel,
/// anchored near a freshly captured region.
@MainActor
final class InstructionPanelController {
    private var panel: KeyablePanel?

    var onCommit: (@MainActor (String) -> Void)?
    var onCancel: (@MainActor () -> Void)?

    /// Window level — must sit above the selection overlay (.screenSaver).
    private static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)

    func show(thumbnail: NSImage, anchorRect: NSRect, index: Int, sizeLabel: String) {
        close()

        let root = InstructionPanelView(
            thumbnail: thumbnail,
            index: index,
            sizeLabel: sizeLabel,
            onCommit: { [weak self] text in
                self?.close()
                self?.onCommit?(text)
            },
            onCancel: { [weak self] in
                self?.close()
                self?.onCancel?()
            }
        )

        let hosting = NSHostingView(rootView: root)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let size = NSSize(width: 420, height: max(fitting.height, 300))

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = Self.level
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting

        self.panel = panel
        position(panel, near: anchorRect)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func position(_ panel: NSPanel, near rect: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let gap: CGFloat = 8
        let margin: CGFloat = 8

        // Candidate placements, nearest-adjacent first: below, above, right, left.
        // Each tucks the panel right against the box, centered on the shared edge.
        let below = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - gap - size.height)
        let above = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + gap)
        let right = NSPoint(x: rect.maxX + gap, y: rect.midY - size.height / 2)
        let left  = NSPoint(x: rect.minX - gap - size.width, y: rect.midY - size.height / 2)

        func fits(_ p: NSPoint) -> Bool {
            p.x >= visible.minX + margin && p.x + size.width <= visible.maxX - margin &&
            p.y >= visible.minY + margin && p.y + size.height <= visible.maxY - margin
        }

        let chosen = [below, above, right, left].first(where: fits) ?? below
        let x = min(max(chosen.x, visible.minX + margin), visible.maxX - size.width - margin)
        let y = min(max(chosen.y, visible.minY + margin), visible.maxY - size.height - margin)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
