import AppKit

/// The menu-bar status item and its menu. All session actions are reachable here.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var session: SessionController?

    private var startItem: NSMenuItem!
    private var addItem: NSMenuItem!
    private var endItem: NSMenuItem!
    private var cancelItem: NSMenuItem!

    /// Built in `rebuildMenu()` and shown on right-click. Not assigned to
    /// `statusItem.menu` so that a plain left-click can trigger `statusItemClicked`.
    private var menu: NSMenu!

    init(session: SessionController) {
        self.session = session
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
    }

    func install() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Cue")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let active = session?.isActive ?? false
        let count = session?.annotations.count ?? 0

        let menu = NSMenu()

        startItem = NSMenuItem(title: "Start Cue Session", action: #selector(start), keyEquivalent: "")
        startItem.target = self
        startItem.isHidden = active
        menu.addItem(startItem)

        addItem = NSMenuItem(title: "Add Capture Box", action: #selector(addBox), keyEquivalent: "")
        addItem.target = self
        addItem.isHidden = !active
        menu.addItem(addItem)

        endItem = NSMenuItem(title: "End Session & Review (\(count))", action: #selector(end), keyEquivalent: "")
        endItem.target = self
        endItem.isHidden = !active
        endItem.isEnabled = count > 0
        menu.addItem(endItem)

        cancelItem = NSMenuItem(title: "Cancel Session", action: #selector(cancel), keyEquivalent: "")
        cancelItem.target = self
        cancelItem.isHidden = !active
        menu.addItem(cancelItem)

        menu.addItem(.separator())

        let browse = NSMenuItem(title: "Browse Sessions…", action: #selector(browse), keyEquivalent: "b")
        browse.target = self
        menu.addItem(browse)

        let folder = NSMenuItem(title: "Open Sessions Folder", action: #selector(openFolder), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cue", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        // Keep the menu for right-click; don't assign it to `statusItem.menu`
        // so that a left-click reaches `statusItemClicked` instead of auto-opening.
        self.menu = menu
        updateButtonAppearance(active: active)
    }

    /// Left-click runs the primary contextual action; right-click (or control-click)
    /// opens the full menu.
    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        if isRightClick {
            showMenu()
        } else if session?.isActive == true {
            // Already in a session → left-click does nothing; use right-click for actions.
        } else {
            session?.startSession()   // primary action: start a session
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        // Temporarily attach the menu so the status item pops it up at the
        // correct position, then detach so plain clicks keep reaching us.
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func updateButtonAppearance(active: Bool) {
        guard let button = statusItem.button else { return }
        let name = active ? "viewfinder.circle.fill" : "viewfinder"
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Cue")
        button.image?.isTemplate = true
    }

    @objc private func start() { session?.startSession() }
    @objc private func addBox() { session?.beginCapture() }
    @objc private func end() { session?.endSession() }
    @objc private func cancel() { session?.cancelSession() }
    @objc private func browse() { LibraryWindowController.shared.show() }
    @objc private func openFolder() { Exporter.openSessionsRoot() }
    @objc private func quit() { NSApp.terminate(nil) }
}
