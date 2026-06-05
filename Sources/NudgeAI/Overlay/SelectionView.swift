import AppKit

/// The full-screen view the user drags across to choose a region.
/// Dims the screen and "punches a hole" where the current selection is.
final class SelectionView: NSView {
    /// Called with a selection rect in AppKit GLOBAL coordinates on mouse-up.
    var onSelect: (@MainActor (NSRect) -> Void)?
    /// Called when the user presses Escape.
    var onCancel: (@MainActor () -> Void)?

    /// Origin of the window in global coordinates, so we can convert
    /// local view points to global screen points.
    var windowGlobalOrigin: NSPoint = .zero

    private var startPoint: NSPoint?
    private var currentRect: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(origin: startPoint!, size: .zero)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            startPoint = nil
            currentRect = nil
            needsDisplay = true
        }
        guard let local = currentRect, local.width >= 3, local.height >= 3 else { return }
        let global = NSRect(
            x: local.origin.x + windowGlobalOrigin.x,
            y: local.origin.y + windowGlobalOrigin.y,
            width: local.width,
            height: local.height
        )
        onSelect?(global)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        NSBezierPath(rect: bounds).fill()

        guard let sel = currentRect, sel.width > 0, sel.height > 0 else {
            drawHint()
            return
        }

        // Punch a transparent hole where the selection is.
        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState()
            ctx.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(rect: sel).fill()
            ctx.restoreGraphicsState()
        }

        // Border.
        let path = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        drawDimensionBadge(for: sel)
    }

    private func drawHint() {
        let text = "Drag to select a region   •   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]
        let size = (text as NSString).size(withAttributes: attrs)

        // The overlay window spans every display, so a single bounds-centered
        // hint can land in the gap between monitors or on the wrong one. Draw
        // one copy centered on each screen — converting each screen's AppKit
        // frame into the overlay view's local coordinates.
        for screen in NSScreen.screens {
            let local = NSRect(
                x: screen.frame.minX - windowGlobalOrigin.x,
                y: screen.frame.minY - windowGlobalOrigin.y,
                width: screen.frame.width,
                height: screen.frame.height
            )
            let origin = NSPoint(
                x: local.midX - size.width / 2,
                y: local.midY - size.height / 2
            )
            (text as NSString).draw(at: origin, withAttributes: attrs)
        }
    }

    private func drawDimensionBadge(for sel: NSRect) {
        let text = "\(Int(sel.width)) × \(Int(sel.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        let badge = NSRect(
            x: sel.minX,
            y: max(sel.minY - textSize.height - 2 * pad - 4, 4),
            width: textSize.width + 2 * pad,
            height: textSize.height + 2 * pad
        )
        let bg = NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.setFill()
        bg.fill()
        (text as NSString).draw(at: NSPoint(x: badge.minX + pad, y: badge.minY + pad), withAttributes: attrs)
    }
}
