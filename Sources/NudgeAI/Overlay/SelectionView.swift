import AppKit

/// One per-display "dim + drag" view. Mouse events are reported to the
/// `controller`, which owns shared drag state across all displays. Drawing
/// pulls from that shared state so a selection started on one display
/// continues to render on every display the rect intersects.
final class SelectionView: NSView {
    weak var controller: SelectionOverlayController?

    /// Origin of this view's window in global AppKit coordinates. Used to
    /// translate the shared global selection rect into the view's local
    /// coordinate space when drawing.
    var windowGlobalOrigin: NSPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // MARK: Mouse — delegate to the controller, using global coordinates so
    // it doesn't matter which window/screen the cursor is over.

    override func mouseDown(with event: NSEvent) {
        controller?.beginDrag(at: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.updateDrag(to: NSEvent.mouseLocation)
    }

    override func mouseUp(with event: NSEvent) {
        controller?.endDrag()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            controller?.cancelDrag()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        NSBezierPath(rect: bounds).fill()

        guard let global = controller?.currentSelectionRect,
              global.width > 0, global.height > 0 else {
            drawHint()
            return
        }

        // Convert the global rect to this view's local coordinates. Parts
        // that fall outside the view's bounds simply don't render (the
        // `local` rect can extend off-view; AppKit handles clipping).
        let local = NSRect(
            x: global.origin.x - windowGlobalOrigin.x,
            y: global.origin.y - windowGlobalOrigin.y,
            width: global.width,
            height: global.height
        )

        // Only do the hole-punch and border on a view that the rect actually
        // intersects — otherwise we'd paint a 0-area cutout for nothing.
        guard local.intersects(bounds) else { return }

        if let ctx = NSGraphicsContext.current {
            ctx.saveGraphicsState()
            ctx.compositingOperation = .copy
            NSColor.clear.setFill()
            NSBezierPath(rect: local).fill()
            ctx.restoreGraphicsState()
        }

        let path = NSBezierPath(rect: local.insetBy(dx: -0.5, dy: -0.5))
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        drawDimensionBadge(localRect: local, globalRect: global)
    }

    private func drawHint() {
        let text = "Drag to select a region   •   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padX: CGFloat = 24
        let padY: CGFloat = 14
        // Each view is sized to its own screen, so view center == screen center.
        let pill = NSRect(
            x: bounds.midX - (textSize.width + 2 * padX) / 2,
            y: bounds.midY - (textSize.height + 2 * padY) / 2,
            width: textSize.width + 2 * padX,
            height: textSize.height + 2 * padY
        )
        let radius = pill.height / 2
        let bg = NSBezierPath(roundedRect: pill, xRadius: radius, yRadius: radius)
        NSColor.black.withAlphaComponent(0.7).setFill()
        bg.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        bg.lineWidth = 1
        bg.stroke()
        (text as NSString).draw(
            at: NSPoint(x: pill.minX + padX, y: pill.minY + padY),
            withAttributes: attrs
        )
    }

    private func drawDimensionBadge(localRect local: NSRect, globalRect global: NSRect) {
        let text = "\(Int(global.width)) × \(Int(global.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        let badge = NSRect(
            x: local.minX,
            y: max(local.minY - textSize.height - 2 * pad - 4, 4),
            width: textSize.width + 2 * pad,
            height: textSize.height + 2 * pad
        )
        let bg = NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4)
        NSColor.controlAccentColor.setFill()
        bg.fill()
        (text as NSString).draw(at: NSPoint(x: badge.minX + pad, y: badge.minY + pad), withAttributes: attrs)
    }
}
