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
            ZStack {
                Circle()
                    .fill(backgroundFill)
                Circle()
                    .stroke(strokeColor, lineWidth: isListening ? 0 : 1)
                Image(systemName: symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(symbolColor)
            }
            .frame(width: 32, height: 32)
            .opacity(isListening ? pulseOpacity : 1.0)
            .animation(isListening ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                       value: pulseOpacity)
            .onAppear { if isListening { pulseOpacity = 0.55 } }
            .onChange(of: isListening) { _, active in
                pulseOpacity = active ? 0.55 : 1.0
            }
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
    }

    // MARK: - Visual state

    @State private var pulseOpacity: Double = 1.0

    private var isListening: Bool {
        dictation.state == .listening || dictation.state == .preparing
    }

    private var symbolName: String {
        isListening ? "mic.fill" : "mic"
    }

    private var symbolColor: Color {
        switch dictation.state {
        case .listening, .preparing: return .white
        case .denied, .failed:       return .orange
        default:                     return .secondary
        }
    }

    private var backgroundFill: Color {
        switch dictation.state {
        case .listening, .preparing: return .red
        case .denied, .failed:       return Color.orange.opacity(0.15)
        default:                     return Color(nsColor: .controlBackgroundColor)
        }
    }

    private var strokeColor: Color {
        switch dictation.state {
        case .denied, .failed: return .orange.opacity(0.55)
        default:               return Color(nsColor: .separatorColor)
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
