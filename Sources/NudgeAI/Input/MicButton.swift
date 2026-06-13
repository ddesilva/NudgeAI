import SwiftUI
import AppKit

/// Small SF-symbol button that drives a `SpeechDictation` and writes live
/// partial transcripts into the bound `text` at the field's current caret.
/// Drop it into the bottom-trailing corner of any editor.
struct MicButton: View {
    @Binding var text: String
    var characterCap: Int? = nil

    @StateObject private var dictation = SpeechDictation()
    @State private var insertionStart: Int = 0
    @State private var lastWrittenLength: Int = 0

    var body: some View {
        Button(action: toggle) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(symbolColor)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(isListening ? 0.95 : 0.7))
                )
                .overlay(
                    Circle()
                        .stroke(symbolColor.opacity(0.25), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onChange(of: dictation.partial) { _, partial in
            applyPartial(partial)
        }
    }

    // MARK: - Visual state

    private var isListening: Bool {
        dictation.state == .listening || dictation.state == .preparing
    }

    private var symbolName: String {
        isListening ? "mic.fill" : "mic"
    }

    private var symbolColor: Color {
        switch dictation.state {
        case .listening, .preparing: .red
        case .denied, .failed:       .orange
        default:                     .secondary
        }
    }

    private var helpText: String {
        switch dictation.state {
        case .idle:                    "Dictate instruction"
        case .preparing:               "Starting…"
        case .listening:               "Listening — click to stop"
        case .denied(.microphone):     "Microphone access denied. Click to open System Settings."
        case .denied(.speech):         "Speech Recognition access denied. Click to open System Settings."
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
}
