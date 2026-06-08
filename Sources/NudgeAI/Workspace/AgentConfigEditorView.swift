import SwiftUI

struct AgentConfigEditorView: View {
    @State var config: AgentConfigFile
    var onSave: (AgentConfigFile) -> Void
    var onCancel: () -> Void

    @State private var selectedKey: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                list
                Divider()
                editor
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Save") { onSave(config) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(config.agents.isEmpty)
            }
            .padding(10)
        }
        .frame(width: 640, height: 380)
        .onAppear { selectedKey = selectedKey ?? config.agents.first?.key }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Agents").font(.headline).padding(10)
            List(selection: $selectedKey) {
                ForEach(config.agents) { agent in
                    Text(agent.displayName).tag(agent.key as String?)
                }
            }
            HStack {
                Button {
                    let new = AgentConfigFile.Agent(
                        key: "agent-\(config.agents.count + 1)",
                        displayName: "New Agent",
                        binary: "/usr/local/bin/claude",
                        args: []
                    )
                    config.agents.append(new)
                    selectedKey = new.key
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    guard let key = selectedKey else { return }
                    config.agents.removeAll { $0.key == key }
                    selectedKey = config.agents.first?.key
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selectedKey == nil)
                Spacer()
            }
            .padding(8)
        }
        .frame(width: 220)
    }

    @ViewBuilder
    private var editor: some View {
        if let idx = config.agents.firstIndex(where: { $0.key == selectedKey }) {
            let bindings = $config.agents[idx]
            Form {
                TextField("Key (unique)", text: bindings.key)
                TextField("Display name", text: bindings.displayName)
                TextField("Binary path", text: bindings.binary)
                TextField("Arguments (space-separated)",
                          text: Binding(
                            get: { bindings.args.wrappedValue.joined(separator: " ") },
                            set: { bindings.args.wrappedValue = $0.split(separator: " ").map(String.init) }
                          ))
                Toggle("Set as default",
                       isOn: Binding(
                            get: { config.defaultAgentKey == bindings.key.wrappedValue },
                            set: { config.defaultAgentKey = $0 ? bindings.key.wrappedValue : config.defaultAgentKey }
                       ))
            }
            .formStyle(.grouped)
        } else {
            Color.clear
                .overlay(Text("No agent selected").foregroundStyle(.secondary))
        }
    }
}
