import AppKit

/// Reads the current caret/selection of whichever `NSTextView` is the first
/// responder. Used by `MicButton` to decide where to insert dictated text.
///
/// We deliberately don't observe — we read on demand at the moment dictation
/// starts, then use that range as the static insertion point for the whole
/// dictation session. SwiftUI's `TextEditor` / `TextField` hide their backing
/// `NSTextView`; the first-responder walk is the simplest way to reach it.
enum FocusedSelection {
    /// `nil` when no text view is focused (shouldn't happen in practice since
    /// the mic button lives inside an editor that's focused when clicked).
    static func current() -> NSRange? {
        let responder = NSApp.keyWindow?.firstResponder
        if let view = responder as? NSTextView {
            return view.selectedRange()
        }
        // `NSTextField`'s field editor is an `NSTextView`; check via the
        // window's `fieldEditor(_:for:)` indirection for completeness.
        if let field = responder as? NSText {
            return NSRange(location: field.selectedRange.location, length: field.selectedRange.length)
        }
        return nil
    }
}
