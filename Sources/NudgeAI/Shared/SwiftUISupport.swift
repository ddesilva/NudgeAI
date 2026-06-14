import SwiftUI
import AppKit

extension View {
    /// Marks a view as **purely decorative** — it is removed from hit-testing
    /// so it can never intercept clicks meant for sibling controls.
    ///
    /// Use this on every thumbnail / preview image, *especially* ones using
    /// `.aspectRatio(contentMode: .fill)`. A `.fill` image overflows its frame
    /// (a landscape capture in a 640×160 box renders ~640×360), and both
    /// `.clipShape` and `.clipped()` clip only the *rendering* — NOT the hit
    /// region. The invisible overflow then sits on top of nearby controls and
    /// silently swallows their clicks.
    ///
    /// This is not hypothetical: it is exactly what made the instruction
    /// panel's close (X) button "dead" — the overflowing thumbnail below the
    /// header covered the X's hit area. Decorative imagery should always be
    /// `.decorative()` so that bug class cannot recur.
    func decorative() -> some View {
        allowsHitTesting(false)
    }
}

/// A SwiftUI wrapper around NSVisualEffectView for native vibrancy backgrounds.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}
