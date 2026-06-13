import SwiftUI

// MARK: - AppButtonLabel
//
// Shared label used by both PrimaryButtonStyle and SecondaryButtonStyle.
// Carries optional leading/trailing SF Symbols and a flag that lets the
// secondary style slide its trailing arrow on hover (the primary style
// ignores that flag — it never slides).
struct AppButtonLabel: View {
    fileprivate let title: String
    fileprivate var leadingIcon: String? = nil
    fileprivate var trailingIcon: String? = nil

    // Driven by the parent ButtonStyle via an EnvironmentKey. The label itself
    // does not own hover state; the style does, because the style is what
    // SwiftUI invokes with .onHover and is what we want to keep self-contained.
    fileprivate var trailingOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(title)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 13, weight: .bold))
                    .offset(x: trailingOffset)
            }
        }
        .font(.system(size: 15, weight: .semibold))
    }
}

// MARK: - PrimaryButtonStyle
//
// The blue-gradient CTA. One per surface. Carries the glow shadow.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(background(pressed: pressed))
            .overlay(topHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: shadowColor(pressed: pressed),
                radius: shadowRadius(pressed: pressed),
                y: shadowY(pressed: pressed)
            )
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
            }
    }

    // The gradient brightens on hover and darkens on press.
    private func background(pressed: Bool) -> some View {
        let topBase    = Color(red: 0.20, green: 0.45, blue: 1.00)
        let bottomBase = Color(red: 0.12, green: 0.32, blue: 0.85)

        let top:    Color
        let bottom: Color
        if pressed {
            top    = topBase.opacity(0.92)
            bottom = bottomBase.opacity(0.92)
        } else if isHovered {
            top    = lighten(topBase, by: 0.08)
            bottom = lighten(bottomBase, by: 0.08)
        } else {
            top    = topBase
            bottom = bottomBase
        }

        return LinearGradient(
            colors: [top, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // 1px top-edge sheen — the "lit from above" highlight.
    private var topHighlight: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 1)
            .blendMode(.plusLighter)
            .mask(
                LinearGradient(
                    colors: [Color.white, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }

    private func shadowColor(pressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if pressed   { return Color.blue.opacity(0.35) }
        if isHovered { return Color.blue.opacity(0.55) }
        return Color.blue.opacity(0.45)
    }

    private func shadowRadius(pressed: Bool) -> CGFloat {
        guard isEnabled else { return 0 }
        if pressed   { return 10 }
        if isHovered { return 14 }
        return 12
    }

    private func shadowY(pressed: Bool) -> CGFloat {
        guard isEnabled else { return 0 }
        if pressed   { return 3 }
        if isHovered { return 5 }
        return 4
    }

    private func lighten(_ color: Color, by amount: CGFloat) -> Color {
        // Pull RGB out via NSColor, bump components, rewrap.
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .blue
        let r = min(1.0, ns.redComponent   + amount)
        let g = min(1.0, ns.greenComponent + amount)
        let b = min(1.0, ns.blueComponent  + amount)
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - SecondaryButtonStyle
//
// Dark, bordered. No shadow. Slides its trailing arrow (if any) on hover.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let slide: CGFloat = (isHovered && !pressed && !reduceMotion) ? 4 : 0

        // We re-inject the hover-driven offset into AppButtonLabel via the
        // environment so the label can apply it to its trailing icon. Buttons
        // that wrap a plain Text just ignore it.
        configuration.label
            .environment(\.appButtonTrailingOffset, slide)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(pressed: pressed), lineWidth: 1)
            )
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onHover { hovering in
                isHovered = hovering
            }
    }

    private func backgroundFill(pressed: Bool) -> Color {
        if pressed   { return Color.white.opacity(0.10) }
        if isHovered { return Color.white.opacity(0.07) }
        return Color.white.opacity(0.04)
    }

    private func borderColor(pressed: Bool) -> Color {
        if !isEnabled { return Color.white.opacity(0.06) }
        if pressed    { return Color.white.opacity(0.16) }
        if isHovered  { return Color.white.opacity(0.18) }
        return Color.white.opacity(0.10)
    }
}

// MARK: - Trailing-offset environment key
//
// Used by SecondaryButtonStyle → AppButtonLabel to slide a trailing chevron
// on hover. PrimaryButtonStyle never sets this, so the label sees 0.
fileprivate struct AppButtonTrailingOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    fileprivate var appButtonTrailingOffset: CGFloat {
        get { self[AppButtonTrailingOffsetKey.self] }
        set { self[AppButtonTrailingOffsetKey.self] = newValue }
    }
}

// Re-read the offset inside the label so the trailing icon slides.
// We attach this via a small adapter View that AppButtonLabel uses
// internally; consumers don't need to know about it.
extension AppButtonLabel {
    // Convenience: build the label such that its trailing icon picks up the
    // hover-driven offset from the SecondaryButtonStyle. Use this from
    // callsites — never construct AppButtonLabel directly without it.
    @ViewBuilder
    static func make(_ title: String,
                     leadingIcon: String? = nil,
                     trailingIcon: String? = nil) -> some View {
        _AppButtonLabelHost(title: title,
                            leadingIcon: leadingIcon,
                            trailingIcon: trailingIcon)
    }
}

fileprivate struct _AppButtonLabelHost: View {
    let title: String
    let leadingIcon: String?
    let trailingIcon: String?

    @Environment(\.appButtonTrailingOffset) private var trailingOffset

    var body: some View {
        AppButtonLabel(
            title: title,
            leadingIcon: leadingIcon,
            trailingIcon: trailingIcon,
            trailingOffset: trailingOffset
        )
    }
}

// MARK: - ButtonStyle static convenience

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryApp: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryApp: SecondaryButtonStyle { SecondaryButtonStyle() }
}
