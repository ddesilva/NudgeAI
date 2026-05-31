import SwiftUI

@MainActor
final class LibraryModel: ObservableObject {
    @Published var sessions: [SavedSession] = []
    @Published var selection: SavedSession.ID?

    func reload() {
        sessions = SessionStore.loadAll()
        if selection == nil { selection = sessions.first?.id }
        if let sel = selection, !sessions.contains(where: { $0.id == sel }) {
            selection = sessions.first?.id
        }
    }

    var selected: SavedSession? {
        sessions.first { $0.id == selection }
    }
}

/// A two-pane browser for past Cue sessions.
struct LibraryView: View {
    @StateObject private var model = LibraryModel()
    @State private var copied = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 820, minHeight: 540)
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .cueSessionsChanged)) { _ in
            model.reload()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        Group {
            if model.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No sessions yet")
                        .font(.headline)
                    Text("Start a Cue session from the menu bar to capture your first set of regions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.sessions, selection: $model.selection) { session in
                    sidebarRow(session).tag(session.id)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.reload()
                } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
            }
        }
    }

    private func sidebarRow(_ session: SavedSession) -> some View {
        HStack(spacing: 10) {
            thumb(session.firstThumbnail)
                .frame(width: 52, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(session.count == 1 ? "1 capture" : "\(session.count) captures")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let session = model.selected {
            VStack(spacing: 0) {
                detailHeader(session)
                Divider()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(session.items) { item in
                            detailRow(session, item)
                        }
                    }
                    .padding(16)
                }
            }
        } else {
            Text("Select a session")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ session: SavedSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName).font(.headline)
                Text(session.folder.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
            Button {
                Exporter.copyPromptToClipboard(session.promptText)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { copied = false }
                }
            } label: { Label("Copy Prompt", systemImage: "doc.on.clipboard") }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([session.folder])
            } label: { Label("Reveal", systemImage: "folder") }

            Button(role: .destructive) {
                SessionStore.delete(session)
                model.reload()
            } label: { Label("Delete", systemImage: "trash") }
        }
        .padding(12)
    }

    private func detailRow(_ session: SavedSession, _ item: SavedSessionItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(item.index)")
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            thumb(session.image(for: item))
                .frame(width: 220, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1)))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.sizeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(item.displayInstruction)
                    .font(.body)
                    .foregroundStyle(item.instruction.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    @ViewBuilder
    private func thumb(_ image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.06))
                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
        }
    }
}
