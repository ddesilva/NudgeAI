import SwiftUI

/// SwiftUI review/preview UI: every captured region with its editable
/// instruction, plus reorder/delete and export actions.
struct ReviewView: View {
    @ObservedObject var session: SessionController
    var onExport: @MainActor () -> Void
    var onClose: @MainActor () -> Void

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
                    row(index: index, annotation: annotation)
                }
            }
            .padding(12)
        }
    }

    private func row(index: Int, annotation: Annotation) -> some View {
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

            VStack(alignment: .leading, spacing: 6) {
                Text(annotation.sizeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                TextEditor(text: binding(for: index))
                    .font(.body)
                    .frame(minHeight: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }

            VStack(spacing: 6) {
                Button { move(index, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(index == 0)
                Button { move(index, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(index == session.annotations.count - 1)
                Button(role: .destructive) { delete(index) } label: { Image(systemName: "trash") }
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private var footer: some View {
        HStack {
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            Spacer()
            Button("Close", action: onClose)
            Button {
                onExport()
                statusMessage = "Exported & prompt copied to clipboard."
            } label: {
                Label("Export & Copy Prompt", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(session.annotations.isEmpty)
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
