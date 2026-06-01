import AppKit

/// A borderless panel that can still become key (so its text field accepts
/// keyboard input) without stealing full app activation.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
