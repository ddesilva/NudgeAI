import SwiftUI

/// The sleek "add instruction" card shown next to a freshly captured region.
struct InstructionPanelView: View {
    let thumbnail: NSImage
    let index: Int
    let sizeLabel: String
    var onCommit: (String) -> Void
    var onCommitAndFinish: (String) -> Void
    var onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var editorFocused: Bool

    private static let maxCharacters = 2000
    private static let panelWidth: CGFloat = 640

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            preview
            sectionHeader
            editor
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
            Text("Box \(index)")
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

    private var sectionHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pencil.line")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Describe the change")
                    .font(.system(size: 14, weight: .semibold))
                Text("Provide clear instructions for what you'd like to change in this highlighted area.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                // Padding matches where TextEditor's first glyph renders:
                // TextEditor outer 7pt + NSTextView's 5pt lineFragmentPadding
                // = 12pt left; outer 5pt = 5pt top.
                Text("Describe the change you want for this highlighted area…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.top, 5)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
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
                            commitAndFinish()
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

            // Character counter, bottom-right inside the editor frame.
            Text("\(text.count) / \(Self.maxCharacters)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(text.count >= Self.maxCharacters ? .red : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .frame(height: 110)
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
        HStack(spacing: 10) {
            Spacer(minLength: 8)

            Button(action: commitAndFinish) {
                Text("Save & Done")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .fixedSize()
            .help("Save this instruction and end the session (⌘⏎)")

            Button(action: commit) {
                HStack(spacing: 6) {
                    Text("Save & Next")
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
}
