import AppKit
import SwiftUI

/// `NSHostingView` that always accepts the first mouse click. Used inside
/// `.nonactivatingPanel`s so the first click on a button isn't swallowed by
/// AppKit's "click to focus the window" path before the button fires.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
