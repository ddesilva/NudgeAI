// Sources/NudgeAI/Workspace/WorkspaceTabStripView.swift
import SwiftUI

struct WorkspaceTabStripView: View {
    @ObservedObject var model: WorkspaceSessionsModel
    var onNew: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.sessions) { session in
                tab(for: session)
            }
            Button(action: onNew) {
                Image(systemName: "plus")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    @ViewBuilder
    private func tab(for session: WorkspaceSession) -> some View {
        let isActive = session.id == model.activeID
        HStack(spacing: 6) {
            Text(session.record.name).font(.system(size: 12))
            Button {
                model.close(session)
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.activeID = session.id }
    }
}
