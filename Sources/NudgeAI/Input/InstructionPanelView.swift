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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            preview
            editor
            footer
        }
        .frame(width: 420)
        .background(VisualEffectView(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { editorFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "viewfinder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Box \(index)")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(sizeLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var preview: some View {
        // Build the layout on a Color.clear that we size explicitly, then
        // overlay the image. With `.aspectRatio(.fill)`, a tiny thumbnail
        // (e.g. 90×18) proposes a 600×120 layout size — without an explicit
        // bounding container that ratio leaks up through the VStack, pushes
        // the panel wider than 420, and the hosting view clips content on the
        // left edge of the panel.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .overlay(
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Describe the change for this region…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .focused($editorFocused)
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
        }
        .frame(height: 92)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            keycap("⏎")
            Text("save").foregroundStyle(.secondary)
            keycap("⌘⏎")
            Text("done").foregroundStyle(.secondary)
            keycap("esc")
            Text("cancel").foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(action: commitAndFinish) {
                Text("Save & Done")
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize()
            .help("Save this instruction and end the session (⌘⏎)")

            Button(action: commit) {
                Text("Save & Next")
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .fixedSize()
            .help("Save this instruction and capture another region (⏎)")
        }
        .font(.system(size: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func keycap(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
    }

    private func commit() {
        onCommit(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func commitAndFinish() {
        onCommitAndFinish(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
