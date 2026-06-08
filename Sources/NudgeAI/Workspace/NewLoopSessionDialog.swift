// Sources/NudgeAI/Workspace/NewLoopSessionDialog.swift
import SwiftUI
import AppKit

struct NewLoopSessionDialog: View {
    let agents: [AgentConfigFile.Agent]
    var lastUsedAgentKey: String?
    var lastUsedCwd: String?
    var onCreate: (_ name: String, _ cwd: String, _ agent: AgentConfigFile.Agent) -> Void
    var onCancel: () -> Void

    @State private var name: String = ""
    @State private var cwd: String = ""
    @State private var agentKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New session").font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Project folder").font(.system(size: 11, weight: .semibold))
                HStack {
                    Text(cwd.isEmpty ? "Choose…" : cwd)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(cwd.isEmpty ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choose…", action: pickFolder)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Agent").font(.system(size: 11, weight: .semibold))
                Picker("", selection: $agentKey) {
                    ForEach(agents) { agent in
                        Text(agent.displayName).tag(agent.key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(agents.isEmpty)
                if agents.isEmpty {
                    Text("No agents configured — open Settings → Workspace to add one.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.system(size: 11, weight: .semibold))
                TextField("e.g. fix-onboarding-empty-state", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    guard !cwd.isEmpty,
                          let agent = agents.first(where: { $0.key == agentKey }) else { return }
                    let finalName = name.isEmpty ? defaultName(from: cwd) : name
                    onCreate(finalName, cwd, agent)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cwd.isEmpty || agents.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            cwd = lastUsedCwd ?? ""
            agentKey = lastUsedAgentKey ?? agents.first?.key ?? ""
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            cwd = url.path
        }
    }

    private func defaultName(from cwd: String) -> String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
