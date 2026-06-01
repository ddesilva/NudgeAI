import AppKit
import SwiftUI

/// Hosts the sleek SwiftUI `InstructionPanelView` in a borderless key panel,
/// anchored near a freshly captured region.
@MainActor
final class InstructionPanelController {
    private var panel: KeyablePanel?

    var onCommit: (@MainActor (String) -> Void)?
    var onCommitAndFinish: (@MainActor (String) -> Void)?
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
            onCommitAndFinish: { [weak self] text in
                self?.close()
                self?.onCommitAndFinish?(text)
            },
            onCancel: { [weak self] in
                self?.close()
                self?.onCancel?()
            }
        )

        // Give the hosting view its target width *before* asking SwiftUI to
        // lay out, otherwise `fittingSize` is measured at .zero and the
        // content lands at the wrong width — the header/footer end up
        // clipped on the left and the size badge drifts toward the center.
        // The bug is timing-dependent and shows up randomly across builds.
        let width: CGFloat = 420
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let size = NSSize(width: width, height: max(fitting.height, 300))

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
        // Pick the screen that overlaps the rect the most; fall back to the
        // screen under the rect's centre, then to the main screen. Picking by
        // "first intersection" can pick the wrong display for boxes that
        // straddle two monitors.
        let screens = NSScreen.screens
        let screen = screens.max(by: { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }) ?? screens.first(where: { $0.frame.contains(NSPoint(x: rect.midX, y: rect.midY)) })
          ?? NSScreen.main
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
        // Clamp by enforcing the *upper* bound first, then the lower bound, so
        // the left/top edge is always inside the visible frame. The previous
        // min(max(...)) order could place the panel off the left edge when
        // the candidate sat far enough left of `visible.minX`.
        let maxX = visible.maxX - size.width - margin
        let maxY = visible.maxY - size.height - margin
        let x = max(visible.minX + margin, min(chosen.x, maxX))
        let y = max(visible.minY + margin, min(chosen.y, maxY))
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private extension NSRect {
    var area: CGFloat { width * height }
}
