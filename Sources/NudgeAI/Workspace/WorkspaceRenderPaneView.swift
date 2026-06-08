// Sources/NudgeAI/Workspace/WorkspaceRenderPaneView.swift
import SwiftUI

struct WorkspaceRenderPaneView: View {
    enum SubTab: Hashable { case plan, preview }
    @State private var active: SubTab = .plan

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("Plan", value: .plan)
                tabButton("Preview", value: .preview)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .overlay(Divider(), alignment: .bottom)

            ZStack {
                Color(nsColor: .textBackgroundColor)
                VStack(spacing: 6) {
                    Text(active == .plan ? "Plan" : "Preview")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Available once the agent calls the matching MCP tool.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text("(v0.3 ships render_plan; v0.4 ships open_preview)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func tabButton(_ title: String, value: SubTab) -> some View {
        Button {
            active = value
        } label: {
            Text(title)
                .font(.system(size: 11, weight: active == value ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(active == value ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }
}
