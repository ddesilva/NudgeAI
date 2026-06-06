import AppKit
import ApplicationServices

/// Delivers a prompt to a chosen target: copy to clipboard, activate the
/// target app, then synthesize ⌘V so the prompt lands in whatever input is
/// focused. Auto-paste needs Accessibility permission; without it the
/// keystroke silently no-ops and the user pastes manually.
@MainActor
enum SendDispatcher {
    enum Target {
        case clipboard
        case session(AgentSession)
    }

    @discardableResult
    static func send(prompt: String, to target: Target) -> String {
        Exporter.copyPromptToClipboard(prompt)

        switch target {
        case .clipboard:
            return "Prompt copied to clipboard."
        case .session(let session):
            if let app = NSRunningApplication(processIdentifier: session.appPID) {
                // `.activateAllWindows` is the modern equivalent of
                // `.activateIgnoringOtherApps` and actually pulls the target
                // forward; the no-options call is cooperative and silently
                // no-ops on Sonoma/Sequoia when another app is frontmost.
                app.activate(options: [.activateAllWindows])
            }
            // macOS activation is async — pasting immediately would land in
            // the previously-frontmost app. Give the target ~180ms to come
            // forward, then synthesize ⌘V. Prompting for Accessibility
            // surfaces the system dialog on first use; subsequent denials
            // don't re-prompt, so this is safe to call every time.
            let prompted = ensureAccessibility()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                postPasteKeystroke()
            }
            if !prompted {
                return "Sent to \(session.displayTitle). Grant Accessibility to auto-paste."
            }
            return "Sent to \(session.displayTitle)."
        }
    }

    /// `true` if the process is already Accessibility-trusted. When it isn't,
    /// requests the system prompt so the user can grant it. Returns the
    /// current trust state — callers can fall back to "clipboard only" UX
    /// when this returns `false`.
    private static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    private static func postPasteKeystroke() {
        // V is virtual keycode 9 on macOS (ANSI layout). Posting via
        // cgAnnotatedSessionEventTap delivers to the focused app rather
        // than the HID event stream, which is what we want for paste.
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
