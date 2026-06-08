// Sources/NudgeAI/Workspace/WorkspaceStatusRowView.swift
import SwiftUI

struct WorkspaceStatusRowView: View {
    @ObservedObject var session: WorkspaceSession

    var body: some View {
        HStack(spacing: 14) {
            Text("cwd: \(session.record.cwd)")
            Text("agent: \(session.record.agent.key)")
            if let code = session.ptyExitCode {
                Text("exited \(code)").foregroundStyle(.red)
            } else {
                Text("running").foregroundStyle(.green)
            }
            Spacer(minLength: 0)
            // MCP indicator placeholder for v0.3.
            Text("MCP: —").foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}
