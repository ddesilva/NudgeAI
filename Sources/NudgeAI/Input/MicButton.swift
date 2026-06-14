import SwiftUI
import AppKit

/// Core mic control. Takes an injected `SpeechDictation` so a host (the
/// instruction panel) can share the same recording state with the equalizer.
/// Most callers use the `MicButton` wrapper below, which owns the dictation.
struct MicButtonCore: View {
    @ObservedObject var dictation: SpeechDictation
    @Binding var text: String
    var characterCap: Int? = nil

    @State private var insertionStart: Int = 0
    @State private var lastWrittenLength: Int = 0
    @State private var dictationOffAlertShown: Bool = false

    var body: some View {
        Button(action: toggle) {
            ZStack {
                if isListening {
                    // Outer ring that brightens + grows with the live mic level.
                    Circle()
                        .stroke(Color.nudgeRecording.opacity(0.30 + 0.45 * Double(dictation.audioLevel)),
                                lineWidth: 2)
                        .scaleEffect(1.16 + 0.12 * CGFloat(dictation.audioLevel))
                        .blur(radius: 3)
                        .animation(.easeOut(duration: 0.12), value: dictation.audioLevel)
                    // Dark centre disc so the white glyph + blue ring read like
                    // the reference image.
                    Circle().fill(Color.black.opacity(0.85))
                    Circle()
                        .stroke(Color.nudgeRecording, lineWidth: 3)
                        .shadow(color: Color.nudgeRecording.opacity(0.8), radius: 8)
                } else {
                    Circle().fill(backgroundFill)
                    Circle().stroke(strokeColor, lineWidth: 1)
                }
                Image(systemName: symbolName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(symbolColor)
            }
            .frame(width: 64, height: 64)
            .animation(.easeInOut(duration: 0.2), value: isListening)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onHover { hovering in
            // The button sits on top of a TextEditor/TextField whose tracking
            // rect sets the I-beam cursor; we need to override that whenever
            // the mouse is actually over the mic.
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onChange(of: dictation.partial) { _, partial in
            applyPartial(partial)
        }
        .onChange(of: dictation.state) { _, newState in
            if case .dictationOff = newState, !dictationOffAlertShown {
                dictationOffAlertShown = true
                presentDictationOffAlert()
            }
        }
    }

    // MARK: - Visual state

    private var isListening: Bool {
        dictation.state == .listening || dictation.state == .preparing
    }

    private var symbolName: String {
        switch dictation.state {
        case .listening, .preparing: return "mic.fill"
        case .denied, .failed, .dictationOff: return "mic.slash.fill"
        default: return "mic"
        }
    }

    private var symbolColor: Color {
        switch dictation.state {
        case .listening, .preparing:          return .white
        case .denied, .failed, .dictationOff: return .white
        default:                              return .secondary
        }
    }

    private var backgroundFill: Color {
        // Only consulted in the non-listening branch; listening draws its own
        // dark disc + blue ring, so there is no `.listening` case here.
        switch dictation.state {
        case .denied, .failed, .dictationOff: return .orange
        default:                              return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var strokeColor: Color {
        switch dictation.state {
        case .denied, .failed, .dictationOff: return .orange
        default:                              return Color(nsColor: .separatorColor)
        }
    }

    private var helpText: String {
        switch dictation.state {
        case .idle:                    "Dictate instruction"
        case .preparing:               "Starting…"
        case .listening:               "Listening — click to stop"
        case .denied(.microphone):     "Microphone access denied. Click to open System Settings."
        case .denied(.speech):         "Speech Recognition access denied. Click to open System Settings."
        case .dictationOff:            "macOS Dictation is turned off. Click to open Keyboard Settings."
        case .failed(let msg):         msg
        }
    }

    // MARK: - Actions

    private func toggle() {
        switch dictation.state {
        case .idle, .failed:
            beginDictation()
        case .listening, .preparing:
            dictation.stop()
        case .denied(let reason):
            // Open Settings and reset to idle. If the user granted permission
            // while away, the next mic click re-checks and proceeds normally.
            openSystemSettings(for: reason)
            dictation.cancel()
        case .dictationOff:
            openKeyboardSettings()
            dictation.cancel()
        }
    }

    private func beginDictation() {
        // Snapshot the insertion point and clear any selected range first so
        // the new partial replaces the selection (matches Dictation UX).
        let nsText = text as NSString
        if let selection = FocusedSelection.current(), selection.location <= nsText.length {
            let safeLocation = min(selection.location, nsText.length)
            let safeEnd = min(selection.location + selection.length, nsText.length)
            insertionStart = safeLocation
            if safeEnd > safeLocation {
                text = nsText.replacingCharacters(
                    in: NSRange(location: safeLocation, length: safeEnd - safeLocation),
                    with: ""
                )
            }
        } else {
            insertionStart = nsText.length
        }
        lastWrittenLength = 0
        dictation.start()
    }

    private func applyPartial(_ partial: String) {
        // Only write while the dictation is the active source of truth. After
        // `stop()` we don't want a late-arriving callback to overwrite anything.
        guard isListening else { return }

        let nsText = text as NSString
        let safeStart = min(insertionStart, nsText.length)
        let safeOldLen = min(lastWrittenLength, nsText.length - safeStart)
        var toInsert = partial as NSString

        if let cap = characterCap {
            let remaining = max(0, cap - (nsText.length - safeOldLen))
            if toInsert.length > remaining {
                toInsert = toInsert.substring(to: remaining) as NSString
            }
        }

        text = nsText.replacingCharacters(
            in: NSRange(location: safeStart, length: safeOldLen),
            with: toInsert as String
        )
        lastWrittenLength = toInsert.length
    }

    private func openSystemSettings(for reason: SpeechDictation.DenyReason) {
        let url: URL?
        switch reason {
        case .microphone:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speech:
            url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        }
        if let url { NSWorkspace.shared.open(url) }
    }

    private func openKeyboardSettings() {
        // Sonoma+ uses the new Settings extension URL; if that fails the
        // workspace falls back to opening System Settings at root.
        let candidates = [
            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.keyboard",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func presentDictationOffAlert() {
        let alert = NSAlert()
        alert.messageText = "Turn on macOS Dictation"
        alert.informativeText = """
        Voice input in Nudge AI uses macOS's built-in Dictation, which is currently off on this Mac.

        Open System Settings → Keyboard → Dictation and turn it on. Once it's enabled, click the microphone again.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Not Now")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openKeyboardSettings()
        }
    }
}

/// Self-owning mic button for callers that don't need to observe recording
/// state (Library draft note, Review per-region fields). Owns the dictation
/// and forwards to `MicButtonCore`. Public init is unchanged from the original
/// `MicButton`, so existing call sites need no edits.
struct MicButton: View {
    @Binding var text: String
    var characterCap: Int? = nil

    @StateObject private var dictation = SpeechDictation()

    var body: some View {
        MicButtonCore(dictation: dictation, text: $text, characterCap: characterCap)
    }
}
