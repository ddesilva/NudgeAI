import SwiftUI

/// SwiftUI sheet body for the Send to picker. Lists detected agent sessions
/// sorted by most-recently-active, with a clipboard fallback at the bottom.
struct SendToPickerView: View {
    @StateObject private var detector = AgentSessionDetector.shared
    var onPick: (SendDispatcher.Target) -> Void
    var onCancel: () -> Void

    @State private var query: String = ""
    @State private var selection: SelectionTag = .clipboard
    /// Once the user clicks a row, stop auto-syncing selection to whatever
    /// the detector currently ranks as best — they made an explicit choice.
    @State private var manualSelection: Bool = false
    /// Re-render the relative-time labels every few seconds.
    @State private var tick = Date()
    private let ticker = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private static let searchThreshold = 10

    private enum SelectionTag: Hashable {
        case session(String)
        case clipboard
    }

    private var filteredSessions: [AgentSession] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return detector.sessions }
        return detector.sessions.filter { session in
            session.displayTitle.lowercased().contains(trimmed)
                || session.appName.lowercased().contains(trimmed)
                || (session.agentName?.lowercased().contains(trimmed) ?? false)
                || (session.workingDirectory?.lowercased().contains(trimmed) ?? false)
        }
    }

    private var showSearch: Bool {
        detector.sessions.count > Self.searchThreshold
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSearch { searchField }
            list
            Divider()
            footer
        }
        .frame(width: 520, height: 480)
        .onAppear {
            detector.refresh()
            syncDefaultSelection()
        }
        .onReceive(ticker) { now in
            tick = now
            detector.refresh()
        }
        // The first refresh() returns immediately with no focused-tab info —
        // the AppleScript probe runs on a background queue and republishes
        // sessions when it completes. Re-sync the default selection so the
        // focused tab gets picked up once it arrives, unless the user has
        // already clicked a row.
        .onChange(of: detector.sessions) { _ in
            if !manualSelection { syncDefaultSelection() }
        }
    }

    /// Pick the top-ranked session, or clipboard if none. The detector's sort
    /// already prioritizes whichever app the user most recently had forward
    /// (with focused-tab and tty-activity as tiebreakers), so first-in-list
    /// is the right default.
    private func syncDefaultSelection() {
        if let first = detector.sessions.first {
            selection = .session(first.id)
        } else {
            selection = .clipboard
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Send to").font(.headline)
                Text("Pick an active agent session. The prompt is copied to your clipboard and the target window is brought to the front.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter by app, agent, or path", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.04))
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 6) {
                if filteredSessions.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredSessions) { session in
                        row(for: session)
                    }
                }

                Divider().padding(.vertical, 4)
                clipboardRow
            }
            .padding(10)
            // Force list to recompute relative-time strings on tick.
            .id(tick)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "viewfinder.slash")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No active agent sessions detected.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Open a terminal and start Claude Code, Codex, Cursor, etc., or use the clipboard fallback below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func row(for session: AgentSession) -> some View {
        let tag = SelectionTag.session(session.id)
        let isSelected = selection == tag

        return Button {
            selection = tag
            manualSelection = true
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: icon(for: session))
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.accentColor.opacity(isSelected ? 0.25 : 0.12)))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(session.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var clipboardRow: some View {
        let tag = SelectionTag.clipboard
        let isSelected = selection == tag

        return Button {
            selection = tag
            manualSelection = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.primary.opacity(isSelected ? 0.18 : 0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Just copy the prompt — I'll paste it.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)

            Button {
                commit()
            } label: {
                Text("Send")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(minWidth: 60)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(currentTarget == nil)
        }
        .padding(14)
    }

    private var currentTarget: SendDispatcher.Target? {
        switch selection {
        case .clipboard:
            return .clipboard
        case .session(let id):
            if let s = detector.sessions.first(where: { $0.id == id }) {
                return .session(s)
            }
            return nil
        }
    }

    private func commit() {
        guard let target = currentTarget else { return }
        onPick(target)
    }

    private func icon(for session: AgentSession) -> String {
        switch session.kind {
        case .terminalAgent: return "terminal.fill"
        case .terminal:      return "terminal"
        case .ide:           return "chevron.left.forwardslash.chevron.right"
        }
    }
}
