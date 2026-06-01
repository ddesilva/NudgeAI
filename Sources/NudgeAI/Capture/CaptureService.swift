import AppKit
import CoreGraphics

/// Screen-recording permission handling + region capture.
///
/// We capture using `CGWindowListCreateImage`, which takes a rectangle in
/// CoreGraphics global coordinates (origin at the top-left of the primary
/// display, y growing downward). Our overlay reports selections in AppKit
/// global coordinates (origin bottom-left), so we flip Y before capturing.
enum CaptureService {

    /// True if the app already has Screen Recording permission.
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system Screen Recording prompt (and adds the app to the
    /// Privacy list). Returns whether access is currently granted.
    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Capture a rectangle given in AppKit global coordinates.
    /// Returns an image plus its true pixel size, or nil on failure.
    static func capture(appKitRect rect: NSRect) -> (image: NSImage, pixelSize: CGSize)? {
        guard rect.width >= 2, rect.height >= 2 else { return nil }
        guard let primary = NSScreen.screens.first else { return nil }

        let primaryHeight = primary.frame.height
        let cgRect = CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        guard let cgImage = CGWindowListCreateImage(
            cgRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        let image = NSImage(cgImage: cgImage, size: rect.size)
        return (image, pixelSize)
    }
}
