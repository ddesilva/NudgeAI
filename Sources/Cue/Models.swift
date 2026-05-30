import AppKit
import CoreGraphics

/// A single captured region plus the instruction the user attached to it.
struct Annotation: Identifiable {
    let id = UUID()
    var image: NSImage
    var instruction: String
    /// Selection rectangle in AppKit global coordinates (origin bottom-left of primary display).
    var rect: CGRect
    /// Pixel dimensions of the captured image (accounts for Retina scale).
    var pixelSize: CGSize
    var createdAt: Date

    /// A short human label like "1280×720 on Built-in Display".
    var sizeLabel: String {
        "\(Int(pixelSize.width))×\(Int(pixelSize.height)) px"
    }
}
