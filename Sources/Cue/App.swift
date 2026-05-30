import AppKit

// Cue — a menu-bar app to highlight regions of the screen and attach
// instructions for a coding agent (Claude / Codex) to act on.
//
// A @MainActor entry point keeps all the AppKit setup on the main actor.

@main
struct CueApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        // `app.delegate` is weak, so keep a strong reference for the app's
        // lifetime. `run()` blocks until termination, so this stays alive.
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
