import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: SessionController!
    private var menuBar: MenuBarController!
    private let cleanup = SessionCleanupScheduler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        session = SessionController()
        menuBar = MenuBarController(session: session)
        session.menuBar = menuBar
        menuBar.install()
        cleanup.start()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
