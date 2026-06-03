import AppKit

/// The menu-bar status item and its menu. All session actions are reachable here.
@MainActor
final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var session: SessionController?

    private var startItem: NSMenuItem!
    private var addItem: NSMenuItem!
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
        Log.info("MenuBarController.install: statusItem visible=\(statusItem.isVisible) length=\(statusItem.length)")
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Nudge AI")
            if image == nil {
                // SF Symbol missing would leave a zero-width button → invisible status item.
                // Fall back to a text title so the user can still find and click it.
                Log.warn("SF Symbol 'viewfinder' unavailable; falling back to title")
                button.title = "Nudge"
            } else {
                button.image = image
                button.image?.isTemplate = true
            }
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            Log.info("status item button installed: image=\(button.image != nil) title=\(button.title)")
        } else {
            Log.error("statusItem.button is nil — menu bar item will not appear")
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        let active = session?.isActive ?? false
        let count = session?.annotations.count ?? 0

        let menu = NSMenu()

        // Toggles between Start (when idle) and End (when a session is open),
        // so clicking it a second time during a session finishes it.
        if active {
            startItem = NSMenuItem(title: "End Session & Review (\(count))", action: #selector(end), keyEquivalent: "")
            startItem.isEnabled = count > 0
        } else {
            var title = "Start Nudge Session"
            if let hk = Preferences.hotkey { title += "   \(hk.displayString)" }
            startItem = NSMenuItem(title: title, action: #selector(start), keyEquivalent: "")
        }
        startItem.target = self
        menu.addItem(startItem)

        addItem = NSMenuItem(title: "Add Capture Box", action: #selector(addBox), keyEquivalent: "")
        addItem.target = self
        addItem.isHidden = !active
        menu.addItem(addItem)

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

        let log = NSMenuItem(title: "Reveal Log in Finder", action: #selector(revealLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        let clear = NSMenuItem(title: clearCacheTitle(), action: #selector(clearCache), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !active
        clear.toolTip = active
            ? "Finish or cancel the current session before clearing cached sessions."
            : "Delete every saved session folder under ~/NudgeAISessions."
        menu.addItem(clear)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Nudge AI", action: #selector(quit), keyEquivalent: "q")
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
            // Second click while a session is open ends it (matches the menu toggle).
            // If nothing was captured, fall back to cancelling so the user isn't stuck.
            if (session?.annotations.isEmpty ?? true) {
                session?.cancelSession()
            } else {
                session?.endSession()
            }
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
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Nudge AI")
        button.image?.isTemplate = true
    }

    @objc private func start() { session?.startSession() }
    @objc private func addBox() { session?.beginCapture() }
    @objc private func end() { session?.endSession() }
    @objc private func cancel() { session?.cancelSession() }
    @objc private func browse() { LibraryWindowController.shared.show() }
    @objc private func openFolder() { Exporter.openSessionsRoot() }
    @objc private func revealLog() { NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL]) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func clearCache() {
        let bytes = SessionStore.totalSizeOnDisk()
        let alert = NSAlert()
        alert.messageText = "Clear cached sessions?"
        alert.informativeText = bytes > 0
            ? "This permanently deletes every Nudge session folder under ~/NudgeAISessions (\(Self.formatBytes(bytes)))."
            : "No cached sessions were found under ~/NudgeAISessions."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        SessionStore.clearAll()
        NotificationCenter.default.post(name: .nudgeSessionsChanged, object: nil)
        rebuildMenu()
    }

    private func clearCacheTitle() -> String {
        let bytes = SessionStore.totalSizeOnDisk()
        guard bytes > 0 else { return "Clear Cached Sessions…" }
        return "Clear Cached Sessions… (\(Self.formatBytes(bytes)))"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }
}
