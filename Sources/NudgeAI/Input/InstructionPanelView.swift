import SwiftUI

/// The sleek "add instruction" card shown next to a freshly captured region.
struct InstructionPanelView: View {
    let thumbnail: NSImage
    let index: Int
    let sizeLabel: String
    var onCommit: (String) -> Void
    var onCommitAndFinish: (String) -> Void
    var onCommitAndDone: (String) -> Void
    var onCommitAndSendTo: (String) -> Void
    var onCancel: () -> Void
    var developerModeEnabled: Bool

    @State private var text: String = ""
    @FocusState private var editorFocused: Bool
    @StateObject private var dictation = SpeechDictation()

    private static let maxCharacters = 2000
    /// Visible to `InstructionPanelController` so the hosting view and SwiftUI
    /// layout agree on the same width. If they disagree, SwiftUI lays out at
    /// this width but AppKit only hit-tests within the hosting view's frame,
    /// silently killing any button that lands outside that frame (the X close
    /// button is the canonical victim because it sits at the right edge).
    static let panelWidth: CGFloat = 640

    private var isRecording: Bool {
        dictation.state == .listening || dictation.state == .preparing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            preview
            editor
                .padding(.top, 16)
            footer
        }
        .frame(width: Self.panelWidth)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .onAppear { editorFocused = true }
    }

    private var header: some View {
        // Close on the LEFT — macOS convention is to put window-close
        // controls where the traffic lights live (top-left), not on the
        // right (which is a Windows pattern). Bonus: moves the X out of the
        // top-right corner of the panel, which is the region where the dead-
        // click bug has been reproducing.
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(IconCircleButtonStyle())
            .help("Cancel this instruction (esc)")

            Text("NudgeAI Instructions \(index)")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(sizeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var preview: some View {
        // Build the layout on a Color.clear that we size explicitly, then
        // overlay the image. With `.aspectRatio(.fill)`, a tiny thumbnail
        // (e.g. 90×18) proposes a 600×120 layout size — without an explicit
        // bounding container that ratio leaks up through the VStack, pushes
        // the panel wider than its declared width, and the hosting view clips
        // content on the left edge.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 160)
            .overlay(
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            // Pure decoration — never let the overflowing `.fill` image's hit
            // region swallow clicks on the header/X above it. See `decorative()`.
            .decorative()
            .padding(.horizontal, 18)
    }

    private var editor: some View {
        // Text area on the left, mic on the right. HStack's default
        // `.center` alignment vertically centers the 64×64 mic in the 174pt
        // box for free. NSTextView's I-beam tracking rect only covers the
        // editor, so the mic keeps the normal arrow/pointing-hand cursor.
        // The character cap is still enforced silently in `onChange` below.
        HStack(alignment: .center, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty && !isRecording {
                    // Placeholder must sit at the same insets as the editor's
                    // first glyph, otherwise it jumps when typing begins.
                    Text("Describe the change you want for this highlighted area…")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
                // Editor stays visible while recording so dictated/typed text is
                // readable; the equalizer rides on top as a translucent layer.
                TextEditor(text: $text)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .focused($editorFocused)
                    .onChange(of: text) { _, newValue in
                        if newValue.count > Self.maxCharacters {
                            text = String(newValue.prefix(Self.maxCharacters))
                        }
                    }
                    // Enter commits; Shift+Enter inserts a newline; ⌘+Enter
                    // commits and ends the session; Esc cancels.
                    .onKeyPress { press in
                        switch press.key {
                        case .return:
                            if press.modifiers.contains(.shift) { return .ignored }
                            if press.modifiers.contains(.command) {
                                if index >= 2 { commitAndDone() } else { commitAndFinish() }
                            } else {
                                commit()
                            }
                            return .handled
                        case .escape:
                            onCancel()
                            return .handled
                        default:
                            return .ignored
                        }
                    }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Live recording equalizer rides on top of the text while dictating.
            .voiceEqualizerOverlay(dictation)

            MicButtonCore(dictation: dictation, text: $text, characterCap: Self.maxCharacters)
                // Nudged in from the edge so the mic lines up better with the
                // trailing "Next" button in the footer below.
                .padding(.trailing, 18)
        }
        .frame(height: 174)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
        .background(
            // A subtle dark fill so the input well reads as distinct from the
            // panel; kept light enough that it never hides the text being typed
            // or dictated (fully blacking it out did, historically).
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    editorFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.1),
                    lineWidth: editorFocused ? 1.5 : 1
                )
                .animation(.easeOut(duration: 0.12), value: editorFocused)
        )
        .padding(.horizontal, 18)
        .onChange(of: dictation.state) { _, newState in
            // Return focus to the editor whenever the mic goes quiet (finished
            // or paused) so the user can carry on typing immediately.
            if newState == .idle || newState == .paused { editorFocused = true }
        }
    }

    private var footer: some View {
        // First capture → Copy to Clipboard (quick single-shot exit, no review).
        // Multi-capture (index ≥ 2) → Done, which finalises and opens the
        // Sessions library so the user can see the full list. Send to… is
        // also hidden once we're multi-capture; the library is the proper
        // dispatch surface for a full session.
        let isMultiCapture = index >= 2

        return HStack(spacing: 10) {
            Spacer(minLength: 8)

            if isMultiCapture {
                Button(action: commitAndDone) {
                    AppButtonLabel.make("Done")
                }
                .buttonStyle(.primaryApp)
                .help("Save this instruction, end the session, and open Sessions (⌘⏎)")
            } else {
                Button(action: commitAndFinish) {
                    AppButtonLabel.make("Copy to Clipboard",
                                        leadingIcon: "doc.on.clipboard")
                }
                .buttonStyle(.primaryApp)
                .help("Save this instruction, copy the prompt to clipboard, end the session (⌘⏎)")

                if developerModeEnabled {
                    Button(action: commitAndSendTo) {
                        AppButtonLabel.make("Send to…",
                                            leadingIcon: "paperplane")
                    }
                    .buttonStyle(.primaryApp)
                    .help("Save the instruction, then pick an active agent session to deliver the prompt to.")
                }
            }

            Button(action: commit) {
                AppButtonLabel.make("Next", trailingIcon: "arrow.right")
            }
            .buttonStyle(.secondaryApp)
            .help("Save this instruction and capture another region (⏎)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    private func commit() {
        onCommit(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitAndFinish() {
        onCommitAndFinish(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitAndDone() {
        onCommitAndDone(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitAndSendTo() {
        onCommitAndSendTo(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Tiny ButtonStyle for icon-only controls inside the instruction panel.
///
/// The `.onHover` is load-bearing, not cosmetic: SwiftUI's hit-testing inside
/// an `NSHostingView` only finds a button when SwiftUI has registered some
/// kind of interaction tracking for it. `Button(.plain)` with image-only
/// content registers nothing, so `NSHostingView.hitTest` returns the host
/// itself and the click dies before reaching the action. Adding `.onHover`
/// installs an `NSTrackingArea` that gives SwiftUI's hit-test something to
/// find — same trick the footer's `PrimaryButtonStyle`/`SecondaryButtonStyle`
/// rely on (and the reason the footer worked while the X didn't).
private struct IconCircleButtonStyle: ButtonStyle {
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(opacity(pressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }

    private func opacity(pressed: Bool) -> Double {
        if pressed { return 0.55 }
        if isHovered { return 0.85 }
        return 1.0
    }
}
