import SwiftUI

/// A very subtle, ambient settings affordance: a faint gear that brightens on
/// hover and opens the Settings window. Deliberately chrome-less (no fill, no
/// border) and low-opacity at rest so it reads as quiet header furniture rather
/// than a call-to-action. Shared by every panel that surfaces it.
struct SettingsGearButton: View {
    /// Resting opacity. Kept low so the gear stays unobtrusive; panels over
    /// busy or translucent backgrounds can nudge it up for legibility.
    var restingOpacity: Double = 0.45

    @State private var hovered = false

    var body: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(hovered ? 0.9 : restingOpacity)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
        .help("Open Settings")
    }
}
