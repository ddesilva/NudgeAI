import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: SessionController!
    private var menuBar: MenuBarController!
    private let cleanup = SessionCleanupScheduler()
    private var hotkeyMonitor: GlobalHotkeyMonitor!
    private var prefsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.startNewSession()
        Log.info("applicationDidFinishLaunching")
        LegacyMigration.run()
        session = SessionController()
        menuBar = MenuBarController(session: session)
        session.menuBar = menuBar
        menuBar.install()
        cleanup.start()

        // The status item carries an autosaveName, so macOS restores the user's
        // chosen position on its own — no launch-time repositioning needed.

        hotkeyMonitor = GlobalHotkeyMonitor { [weak self] in
            self?.toggleSessionFromHotkey()
        }
        hotkeyMonitor.reload()
        Log.info("hotkey monitor reloaded; launch sequence complete")

        // The settings panel posts this when the user changes the hotkey or
        // toggles it off, so we re-register on the fly without a restart.
        prefsObserver = NotificationCenter.default.addObserver(
            forName: .nudgePreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.hotkeyMonitor.reload()
                self?.menuBar.rebuildMenu()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Mirrors the primary left-click behaviour on the status item.
    private func toggleSessionFromHotkey() {
        if session.isActive {
            if session.annotations.isEmpty {
                session.cancelSession()
            } else {
                session.endSession()
            }
        } else {
            session.startSession()
        }
    }
}
