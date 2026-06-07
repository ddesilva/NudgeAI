import AppKit
import SwiftUI

/// Hosts the sleek SwiftUI `InstructionPanelView` in a borderless key panel,
/// anchored near a freshly captured region.
@MainActor
final class InstructionPanelController {
    private var panel: KeyablePanel?

    var onCommit: (@MainActor (String) -> Void)?
    var onCommitAndFinish: (@MainActor (String) -> Void)?
    var onCommitAndDone: (@MainActor (String) -> Void)?
    var onCommitAndSendTo: (@MainActor (String) -> Void)?
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
            onCommitAndDone: { [weak self] text in
                self?.close()
                self?.onCommitAndDone?(text)
            },
            onCommitAndSendTo: { [weak self] text in
                self?.close()
                self?.onCommitAndSendTo?(text)
            },
            onCancel: { [weak self] in
                self?.close()
                self?.onCancel?()
            },
            developerModeEnabled: Preferences.developerModeEnabled
        )

        // Give the hosting view its target width *before* asking SwiftUI to
        // lay out, otherwise `fittingSize` is measured at .zero and the
        // content lands at the wrong width — the header/footer end up
        // clipped on the left and the size badge drifts toward the center.
        // The bug is timing-dependent and shows up randomly across builds.
        //
        // FirstMouseHostingView (rather than plain NSHostingView) so the X
        // close button — and any tap target near a panel edge — fires on the
        // first click instead of being eaten by AppKit's "click to focus" path
        // for the non-activating panel.
        let width: CGFloat = 420
        let hosting = FirstMouseHostingView(rootView: root)
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
        let fullFrame = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = screen?.visibleFrame ?? fullFrame
        let size = panel.frame.size
        let margin: CGFloat = 8

        // Center on the *physical* screen so the panel reads as centered to
        // the eye. Using visibleFrame here would shift the panel away from
        // the dock/menubar (e.g. dock on the right pulls midX leftward),
        // which looks off-center.
        var x = fullFrame.midX - size.width / 2
        var y = fullFrame.midY - size.height / 2

        // Then clamp into the visible frame so we don't end up under the
        // menubar/dock when their inset is large.
        x = max(visible.minX + margin, min(x, visible.maxX - size.width - margin))
        y = max(visible.minY + margin, min(y, visible.maxY - size.height - margin))
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
