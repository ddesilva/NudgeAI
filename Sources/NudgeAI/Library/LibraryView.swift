import SwiftUI
import AppKit

@MainActor
final class LibraryModel: ObservableObject {
    @Published var sessions: [SavedSession] = []
    @Published var selection: String?

    // Honoured on the next reload. Used by "open the library focused on the
    // session we just finished" so the caller doesn't race the load.
    private var pendingSelection: String?

    func reload() {
        sessions = SessionStore.loadAll()
        if let pending = pendingSelection,
           sessions.contains(where: { $0.id == pending }) {
            selection = pending
            pendingSelection = nil
        } else if selection == nil {
            selection = sessions.first?.id
        } else if let sel = selection,
                  !sessions.contains(where: { $0.id == sel }) {
            selection = sessions.first?.id
        }
    }

    /// Queue a session to be selected on the next reload, then reload now.
    /// Safe to call before the session is present on disk: the pending id
    /// sticks until a future reload finds it.
    func select(folder folderPath: String) {
        pendingSelection = folderPath
        reload()
    }

    var selected: SavedSession? {
        sessions.first { $0.id == selection }
    }
}

/// A two-pane browser for past Nudge AI sessions.
struct LibraryView: View {
    var onSendTo: (String) -> Void

    @StateObject private var model = LibraryModel()
    @AppStorage(Preferences.developerModeKey) private var developerModeEnabled: Bool = false

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
        .onReceive(NotificationCenter.default.publisher(for: .nudgeSelectSession)) { note in
            if let path = note.userInfo?["folder"] as? String {
                model.select(folder: path)
            }
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
                List(selection: $model.selection) {
                    Section("Sessions") {
                        ForEach(model.sessions) { session in
                            captureSidebarRow(session).tag(session.id as String?)
                        }
                    }
                }
                // `.sidebar` style gives Finder's inset rounded-pill selection
                // and the small-caps muted section header.
                .listStyle(.sidebar)
                // Hide the List's default opaque background so the .sidebar
                // material below shows through as Finder-style vibrant glass.
                .scrollContentBackground(.hidden)
            }
        }
        // The vibrant sidebar material that Finder uses. `.behindWindow`
        // blending makes it sample the desktop, so the panel reads as a
        // separate sheet of glass floating above the detail pane.
        .background(VisualEffectView(material: .sidebar, blending: .behindWindow).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.reload()
                } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh")
            }
        }
    }

    private func captureSidebarRow(_ session: SavedSession) -> some View {
        HStack(spacing: 8) {
            thumb(session.firstThumbnail)
                .frame(width: 44, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.08)))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayName)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(session.count == 1 ? "1 capture" : "\(session.count) captures")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let saved = model.selected {
            VStack(spacing: 0) {
                actionBar(saved)
                Divider()
                titleStrip(saved)
                Divider()
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(saved.items) { item in
                            detailRow(saved, item)
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

    /// Big-button action row at the top of the detail pane. Pinned to a fixed
    /// height so nothing in the VStack chain can stretch it vertically.
    private func actionBar(_ session: SavedSession) -> some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            Button {
                Exporter.copyPromptToClipboard(session.promptText)
                LibraryWindowController.shared.close()
            } label: {
                AppButtonLabel.make("Copy Prompt",
                                    leadingIcon: "doc.on.clipboard")
            }
            .buttonStyle(.primaryApp)
            .help("Copy this session's prompt to the clipboard")

            if developerModeEnabled {
                Button {
                    onSendTo(session.promptText)
                } label: {
                    AppButtonLabel.make("Send to…", leadingIcon: "paperplane")
                }
                .buttonStyle(.primaryApp)
                .help("Send this session's prompt to an active agent window.")
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([session.folder])
            } label: {
                AppButtonLabel.make("Reveal", leadingIcon: "folder")
            }
            .buttonStyle(.secondaryApp)
            .help("Reveal this session's folder in Finder")

            Button(role: .destructive) {
                SessionStore.delete(session)
                model.reload()
            } label: {
                AppButtonLabel.make("Delete", leadingIcon: "trash")
            }
            .buttonStyle(.secondaryApp)
            .help("Delete this session from disk")
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
    }

    /// Thin title/path strip below the action row. Fixed height so it can't
    /// expand into the captures area.
    private func titleStrip(_ session: SavedSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayName).font(.headline)
            Text(session.folder.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
        // `.decorative()` is required, not cosmetic: the `.fill` image overflows
        // its frame and (because clipping doesn't clip hit-testing) its hit
        // region would otherwise swallow clicks on the adjacent row text,
        // instruction field, and mic button. See `decorative()`.
        Group {
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
        .decorative()
    }
}

// MARK: - InstructionField

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
        // Top-align so a short instruction sits flush with the size label
        // above rather than floating to the vertical centre of the 64pt mic.
        HStack(alignment: .top, spacing: 6) {
            TextField("Add an instruction…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(1...8)
                .foregroundStyle(draft.isEmpty ? Color.secondary : Color.primary)
                .focused($focused)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onChange(of: item.instruction) { _, newValue in
                    // Reload from disk shouldn't clobber what the user is typing.
                    if !focused, newValue != draft { draft = newValue }
                }
            MicButton(text: $draft)
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
