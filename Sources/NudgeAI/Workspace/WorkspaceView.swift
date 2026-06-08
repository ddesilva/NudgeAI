// Sources/NudgeAI/Workspace/WorkspaceView.swift
import SwiftUI

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceSessionsModel
    var onNewSessionRequested: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceTabStripView(model: model, onNew: onNewSessionRequested)
            if let session = model.active {
                WorkspaceStatusRowView(session: session)
                HSplitView {
                    WorkspaceRenderPaneView()
                        .frame(minWidth: 320, idealWidth: 520)
                    TerminalPane(session: session)
                        .frame(minWidth: 360)
                }
            } else {
                emptyState
            }
        }
        .frame(minWidth: 900, minHeight: 540)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No open sessions").font(.title3).foregroundStyle(.secondary)
            Button("New Session…", action: onNewSessionRequested)
                .keyboardShortcut("n", modifiers: .command)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
