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

/// A two-pane browser for past Nudge AI sessions.
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
        .onReceive(NotificationCenter.default.publisher(for: .nudgeSessionsChanged)) { _ in
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
                    Text("Start a Nudge session from the menu bar to capture your first set of regions.")
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName).font(.headline)
                Text(session.folder.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)

            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }

            // Copy is the headline action — primary blue. Reveal/Delete share
            // the same large bordered look as the instruction-panel buttons so
            // the app reads as one design language.
            Button {
                Exporter.copyPromptToClipboard(session.promptText)
                withAnimation { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation { copied = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Copy Prompt")
                }
                .font(.system(size: 15, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fixedSize()
            .help("Copy this session's prompt to the clipboard")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([session.folder])
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Reveal")
                }
                .font(.system(size: 15, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .fixedSize()
            .help("Reveal this session's folder in Finder")

            Button(role: .destructive) {
                SessionStore.delete(session)
                model.reload()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                    Text("Delete")
                }
                .font(.system(size: 15, weight: .semibold))
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .fixedSize()
            .help("Delete this session from disk")
        }
        .padding(14)
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
                InstructionField(session: session, item: item) {
                    model.reload()
                }
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

/// Inline editable instruction for one row in the session detail list.
/// Saves to disk on focus loss (click out / Tab away). Empty text is allowed
/// and falls back to the same "(no instruction)" placeholder the read-only
/// view used to show.
private struct InstructionField: View {
    let session: SavedSession
    let item: SavedSessionItem
    var onSaved: () -> Void

    @State private var draft: String
    @FocusState private var focused: Bool

    init(session: SavedSession, item: SavedSessionItem, onSaved: @escaping () -> Void) {
        self.session = session
        self.item = item
        self.onSaved = onSaved
        _draft = State(initialValue: item.instruction)
    }

    var body: some View {
        TextField("Add an instruction…", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(1...8)
            .foregroundStyle(draft.isEmpty ? Color.secondary : Color.primary)
            .focused($focused)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onChange(of: item.instruction) { _, newValue in
                // Reload from disk shouldn't clobber what the user is typing.
                if !focused, newValue != draft { draft = newValue }
            }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != draft { draft = trimmed }
        guard trimmed != item.instruction else { return }
        do {
            try SessionStore.updateInstruction(in: session, atIndex: item.index, to: trimmed)
            onSaved()
        } catch {
            // Surface the failure by reverting to what's on disk — the next
            // reload will overwrite the draft with the unchanged instruction
            // so the user sees their edit didn't stick.
            draft = item.instruction
        }
    }
}

