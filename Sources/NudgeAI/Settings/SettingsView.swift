import SwiftUI
import AppKit

@MainActor
final class SettingsModel: ObservableObject {
    @Published var hotkey: Hotkey
    @Published var hotkeyEnabled: Bool
    @Published var retentionDays: Int
    @Published var sessionsFolder: URL
    @Published var sessionsFolderIsDefault: Bool
    @Published var prioritizeMenuBar: Bool
    @Published var developerModeEnabled: Bool

    init() {
        let saved = Preferences.hotkey
        self.hotkey = saved ?? Preferences.defaultHotkey
        self.hotkeyEnabled = saved != nil
        self.retentionDays = Preferences.retentionDays
        self.sessionsFolder = Preferences.sessionsFolderURL
        self.sessionsFolderIsDefault = Preferences.sessionsFolderOverride == nil
        self.prioritizeMenuBar = Preferences.prioritizeMenuBar
        self.developerModeEnabled = Preferences.developerModeEnabled
    }

    func setHotkey(_ hk: Hotkey) {
        hotkey = hk
        if hotkeyEnabled { Preferences.hotkey = hk }
    }

    func setEnabled(_ on: Bool) {
        hotkeyEnabled = on
        Preferences.hotkey = on ? hotkey : nil
    }

    func setRetention(_ days: Int) {
        retentionDays = days
        Preferences.retentionDays = days
    }

    func resetHotkey() {
        setHotkey(Preferences.defaultHotkey)
    }

    func setSessionsFolder(_ url: URL) {
        Preferences.sessionsFolderOverride = url
        sessionsFolder = Preferences.sessionsFolderURL
        sessionsFolderIsDefault = false
    }

    func resetSessionsFolder() {
        Preferences.sessionsFolderOverride = nil
        sessionsFolder = Preferences.sessionsFolderURL
        sessionsFolderIsDefault = true
    }

    func setPrioritizeMenuBar(_ on: Bool) {
        prioritizeMenuBar = on
        Preferences.prioritizeMenuBar = on
        if on { requestMenuBarRepin() }
    }

    func setDeveloperMode(_ on: Bool) {
        developerModeEnabled = on
        Preferences.developerModeEnabled = on
    }

    func requestMenuBarRepin() {
        NotificationCenter.default.post(name: .nudgeMenuBarRepinRequested, object: nil)
    }
}

/// SwiftUI settings panel: global hotkey + session retention.
struct SettingsView: View {
    @StateObject private var model = SettingsModel()
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Form {
            Section("Global Hotkey") {
                Toggle("Enable global hotkey", isOn: Binding(
                    get: { model.hotkeyEnabled },
                    set: { model.setEnabled($0) }
                ))

                HStack {
                    Text("Start session")
                    Spacer()
                    Button(action: toggleRecording) {
                        Text(recording ? "Press keys…" : model.hotkey.displayString)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 120)
                    }
                    .disabled(!model.hotkeyEnabled)
                    .help("Click, then press a key combination with at least one modifier.")

                    Button("Reset") { model.resetHotkey() }
                        .disabled(!model.hotkeyEnabled)
                }

                Text("Pressing the hotkey toggles a Nudge session from any app. Plain keys are ignored — use ⌘, ⇧, ⌥, or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sessions") {
                HStack {
                    Text("Keep saved sessions for")
                    Spacer()
                    Stepper(value: Binding(
                        get: { model.retentionDays },
                        set: { model.setRetention($0) }
                    ), in: Preferences.minRetentionDays...Preferences.maxRetentionDays) {
                        Text("\(model.retentionDays) day\(model.retentionDays == 1 ? "" : "s")")
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                }

                Text("Session folders under the storage location older than this are removed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Save sessions to")
                    Text(displayPath(model.sessionsFolder))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }

                HStack {
                    Button("Change…") { chooseFolder() }
                    Button("Reveal in Finder") { revealFolder() }
                    Spacer()
                    Button("Reset") { model.resetSessionsFolder() }
                        .disabled(model.sessionsFolderIsDefault)
                }

                Text("New sessions are written here. Existing folders in the previous location stay where they are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Developer") {
                Toggle("Enable developer mode", isOn: Binding(
                    get: { model.developerModeEnabled },
                    set: { model.setDeveloperMode($0) }
                ))

                Text("Adds a Send to button alongside Copy to Clipboard. Send to lets you push the prompt straight into an active agent session (Claude Code, Codex, Cursor, Claude.ai, …) — Nudge AI detects what's running and you pick the target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Menu Bar") {
                Toggle("Pin to leftmost menu bar position", isOn: Binding(
                    get: { model.prioritizeMenuBar },
                    set: { model.setPrioritizeMenuBar($0) }
                ))

                HStack {
                    Spacer()
                    Button("Re-pin Now") { model.requestMenuBarRepin() }
                }

                Text("On launch (and when you click Re-pin Now), Nudge AI re-creates its menu-bar item so it sits leftmost — the position least likely to be hidden behind the notch when many apps are running. macOS does not allow apps to override which items it hides; use this if Nudge AI's icon disappears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onDisappear { stopRecording() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Pick a folder where Nudge AI should save session captures."
        panel.directoryURL = model.sessionsFolder
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            model.setSessionsFolder(url)
        }
    }

    private func revealFolder() {
        let url = model.sessionsFolder
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func displayPath(_ url: URL) -> String {
        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // ⎋ cancels the recording without changing the hotkey.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let mods = event.modifierFlags
                .intersection([.command, .shift, .option, .control])
            guard !mods.isEmpty else {
                // Plain key — ignore so we don't grab letters meant for typing.
                return nil
            }
            let hk = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            model.setHotkey(hk)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
