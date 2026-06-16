import SwiftUI

/// SwiftUI review/preview UI: every captured region with its editable
/// instruction, plus reorder/delete and export actions.
struct ReviewView: View {
    @ObservedObject var session: SessionController
    var onExport: @MainActor () -> Void
    var onSendTo: @MainActor () -> Void
    var onClose: @MainActor () -> Void
    var developerModeEnabled: Bool

    @State private var statusMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if session.annotations.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    private var header: some View {
        HStack {
            Image(systemName: "viewfinder.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review session").font(.headline)
                Text("\(session.annotations.count) capture\(session.annotations.count == 1 ? "" : "s") — edit, reorder, then export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text("No captures in this session.").foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(session.annotations.enumerated()), id: \.element.id) { index, annotation in
                    ReviewRow(index: index,
                              annotation: annotation,
                              count: session.annotations.count,
                              text: binding(for: index),
                              onMove: move,
                              onDelete: delete)
                }
            }
            .padding(12)
        }
    }

    /// One capture row: thumbnail, editable instruction (with mic + live
    /// equalizer), and reorder/delete controls. Owns its own `SpeechDictation`
    /// so each row can record and visualize independently.
    private struct ReviewRow: View {
        let index: Int
        let annotation: Annotation
        let count: Int
        @Binding var text: String
        let onMove: (Int, Int) -> Void
        let onDelete: (Int) -> Void

        @StateObject private var dictation = SpeechDictation()

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    Spacer()
                }

                Image(nsImage: annotation.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 110)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    // Decorative thumbnail. `.fit` doesn't overflow today, but mark
                    // it so a future switch to `.fill` can't silently eat clicks on
                    // the adjacent editor/mic. See `decorative()`.
                    .decorative()

                VStack(alignment: .leading, spacing: 6) {
                    Text(annotation.sizeLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 8) {
                        TextEditor(text: $text)
                            .font(.system(size: 16))
                            .frame(minHeight: 70)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                            // Live equalizer while dictating into this field.
                            .voiceEqualizerOverlay(dictation, verticalPadding: 8)
                        MicButtonCore(dictation: dictation, text: $text)
                    }
                }

                VStack(spacing: 6) {
                    Button { onMove(index, -1) } label: { Image(systemName: "arrow.up") }
                        .disabled(index == 0)
                    Button { onMove(index, 1) } label: { Image(systemName: "arrow.down") }
                        .disabled(index == count - 1)
                    Button(role: .destructive) { onDelete(index) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        }
    }

    private var footer: some View {
        HStack {
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button(action: onClose) {
                AppButtonLabel.make("Close")
            }
            .buttonStyle(.secondaryApp)

            Button {
                onExport()
                statusMessage = "Exported & prompt copied to clipboard."
            } label: {
                AppButtonLabel.make("Copy to Clipboard",
                                    leadingIcon: "doc.on.clipboard")
            }
            .buttonStyle(.primaryApp)
            .keyboardShortcut(.defaultAction)
            .disabled(session.annotations.isEmpty)

            if developerModeEnabled {
                Button {
                    onSendTo()
                } label: {
                    AppButtonLabel.make("Send to…", leadingIcon: "paperplane")
                }
                .buttonStyle(.primaryApp)
                .disabled(session.annotations.isEmpty)
                .help("Export the session, copy the prompt, and activate the chosen agent's window.")
            }
        }
        .padding(12)
    }

    // MARK: Mutations

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { index < session.annotations.count ? session.annotations[index].instruction : "" },
            set: { if index < session.annotations.count { session.annotations[index].instruction = $0 } }
        )
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard target >= 0, target < session.annotations.count else { return }
        session.annotations.swapAt(index, target)
    }

    private func delete(_ index: Int) {
        guard index < session.annotations.count else { return }
        session.annotations.remove(at: index)
    }
}
