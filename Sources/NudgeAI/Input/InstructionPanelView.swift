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

    private static let maxCharacters = 2000
    private static let panelWidth: CGFloat = 640

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
        HStack(spacing: 10) {
            Image(systemName: "viewfinder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            Text("NudgeAI Instructions \(index)")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text(sizeLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.08)))

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel this instruction (esc)")
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
            .padding(.horizontal, 18)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            // Text area on top, controls strip at the bottom — same rounded
            // background. The NSTextView's I-beam tracking rect only covers
            // the upper ZStack, so the mic gets the normal arrow/pointing-hand
            // cursor in the strip below.
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    // Placeholder must sit at the same insets as the editor's
                    // first glyph, otherwise it jumps when typing begins.
                    Text("Describe the change you want for this highlighted area…")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 7)
                    .padding(.top, 12)
                    .padding(.bottom, 5)
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
                                // ⌘⏎ takes whichever finish action the footer is
                                // currently showing — Copy on the first box, Done
                                // once the session is multi-capture.
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
            .frame(maxHeight: .infinity)

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text("\(text.count) / \(Self.maxCharacters)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(text.count >= Self.maxCharacters ? .red : .secondary)
                MicButton(text: $text, characterCap: Self.maxCharacters)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .padding(.top, 4)
        }
        .frame(height: 174)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
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
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fixedSize()
                .help("Save this instruction, end the session, and open Sessions (⌘⏎)")
            } else {
                Button(action: commitAndFinish) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Copy to Clipboard")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .fixedSize()
                .help("Save this instruction, copy the prompt to clipboard, end the session (⌘⏎)")

                if developerModeEnabled {
                    Button(action: commitAndSendTo) {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane")
                            Text("Send to…")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .fixedSize()
                    .help("Save the instruction, then pick an active agent session to deliver the prompt to.")
                }
            }

            Button(action: commit) {
                HStack(spacing: 6) {
                    Text("Next")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fixedSize()
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
