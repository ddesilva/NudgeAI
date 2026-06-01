import SwiftUI
import AppKit

@MainActor
final class SettingsModel: ObservableObject {
    @Published var hotkey: Hotkey
    @Published var hotkeyEnabled: Bool
    @Published var retentionDays: Int

    init() {
        let saved = Preferences.hotkey
        self.hotkey = saved ?? Preferences.defaultHotkey
        self.hotkeyEnabled = saved != nil
        self.retentionDays = Preferences.retentionDays
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

                Text("Session folders under ~/NudgeAISessions older than this are removed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 320)
        .onDisappear { stopRecording() }
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
