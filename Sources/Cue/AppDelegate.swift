import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var session: SessionController!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        session = SessionController()
        menuBar = MenuBarController(session: session)
        session.menuBar = menuBar
        menuBar.install()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
