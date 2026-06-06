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
            // Prompting for Accessibility surfaces the system dialog on first
            // use; subsequent denials don't re-prompt, so this is safe to call
            // every time.
            let prompted = ensureAccessibility()
            activateAndPaste(session: session)
            if !prompted {
                return "Sent to \(session.displayTitle). Grant Accessibility to auto-paste."
            }
            return "Sent to \(session.displayTitle)."
        }
    }

    /// Activate the target app and synthesize ⌘V once it's actually forward.
    ///
    /// We previously called `NSRunningApplication.activate` directly, but on
    /// Sonoma/Sequoia an app can only yield activation while it is itself the
    /// active app. By the time this runs the picker has already been
    /// `orderOut`-ed and NudgeAI may have lost active status, so the call
    /// silently no-ops — the target never comes forward and ⌘V lands in
    /// whatever app the system picked instead. `NSWorkspace.openApplication`
    /// has the right entitlements to activate any installed app regardless of
    /// caller state, and its completion fires once activation has been
    /// requested, which is a much more reliable cue than a fixed timer.
    private static func activateAndPaste(session: AgentSession) {
        let url: URL? = NSRunningApplication(processIdentifier: session.appPID)?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: session.bundleID)

        guard let url else {
            // No bundle URL — best-effort fall back to direct activation +
            // fixed delay so we at least try.
            NSRunningApplication(processIdentifier: session.appPID)?
                .activate(options: [.activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { postPasteKeystroke() }
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            // Completion fires once the app has been launched/activated, but
            // Electron apps (Cursor, VS Code) still need a beat for their
            // renderer to install focus on the chat input field — pad the
            // wait a bit beyond the cocoa-app value.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { postPasteKeystroke() }
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
