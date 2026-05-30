import AppKit

/// Writes a session to disk and builds the clipboard prompt.
enum Exporter {
    struct Result {
        var folder: URL
        var markdown: String
        var promptForAgent: String
    }

    static var sessionsRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("CueSessions", isDirectory: true)
    }

    static func openSessionsRoot() {
        try? FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(sessionsRoot)
    }

    /// Persist the annotations into a timestamped folder. Returns paths + text.
    @discardableResult
    static func export(annotations: [Annotation], date: Date = Date()) throws -> Result {
        let fm = FileManager.default
        let stamp = folderStamp(date)
        let folder = sessionsRoot.appendingPathComponent("Cue-\(stamp)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        var mdLines: [String] = []
        var promptLines: [String] = []
        mdLines.append("# Cue session — \(displayStamp(date))")
        mdLines.append("")
        mdLines.append("Each item below is a screenshot of a region and the change requested for it.")
        mdLines.append("")

        promptLines.append("I've highlighted regions of my screen and described the change I want for each.")
        promptLines.append("The screenshots are in: \(folder.path)")
        promptLines.append("")

        for (i, ann) in annotations.enumerated() {
            let n = i + 1
            let fileName = String(format: "shot-%02d.png", n)
            let fileURL = folder.appendingPathComponent(fileName)
            try writePNG(ann.image, to: fileURL)

            let note = ann.instruction.isEmpty ? "(no instruction)" : ann.instruction

            mdLines.append("## \(n)")
            mdLines.append("")
            mdLines.append("![\(fileName)](\(fileName))")
            mdLines.append("")
            mdLines.append("- Region: \(ann.sizeLabel)")
            mdLines.append("- **Instruction:** \(note)")
            mdLines.append("")

            promptLines.append("\(n). \(fileURL.path)")
            promptLines.append("   \(note)")
        }

        promptLines.append("")
        promptLines.append("Please open each screenshot and make the requested change.")

        let markdown = mdLines.joined(separator: "\n")
        let prompt = promptLines.joined(separator: "\n")

        try markdown.data(using: .utf8)?.write(to: folder.appendingPathComponent("instructions.md"))
        try prompt.data(using: .utf8)?.write(to: folder.appendingPathComponent("prompt.txt"))
        try writeJSON(annotations: annotations, folder: folder, date: date)

        return Result(folder: folder, markdown: markdown, promptForAgent: prompt)
    }

    static func copyPromptToClipboard(_ prompt: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
    }

    static func copyImageToClipboard(_ image: NSImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    // MARK: Writing helpers

    private static func writePNG(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Cue", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
        }
        try png.write(to: url)
    }

    private static func writeJSON(annotations: [Annotation], folder: URL, date: Date) throws {
        struct Item: Encodable {
            var index: Int
            var file: String
            var instruction: String
            var pixelWidth: Int
            var pixelHeight: Int
        }
        struct Manifest: Encodable {
            var createdAt: String
            var count: Int
            var items: [Item]
        }
        let items = annotations.enumerated().map { i, ann in
            Item(
                index: i + 1,
                file: String(format: "shot-%02d.png", i + 1),
                instruction: ann.instruction,
                pixelWidth: Int(ann.pixelSize.width),
                pixelHeight: Int(ann.pixelSize.height)
            )
        }
        let manifest = Manifest(createdAt: isoStamp(date), count: items.count, items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: folder.appendingPathComponent("cue.json"))
    }

    // MARK: Date formatting (no Date.now reliance beyond passed-in value)

    private static func folderStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    private static func displayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    private static func isoStamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        return f.string(from: date)
    }
}
