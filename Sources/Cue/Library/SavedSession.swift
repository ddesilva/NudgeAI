import AppKit

/// One captured region within a saved session on disk.
struct SavedSessionItem: Identifiable {
    let id = UUID()
    let index: Int
    let instruction: String
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int

    var sizeLabel: String { "\(pixelWidth)×\(pixelHeight) px" }
    var displayInstruction: String {
        instruction.isEmpty ? "(no instruction)" : instruction
    }
}

/// A previously exported session loaded from ~/CueSessions/Cue-<stamp>/.
struct SavedSession: Identifiable {
    let id: String           // folder path
    let folder: URL
    let createdAt: Date
    let displayName: String
    let items: [SavedSessionItem]

    var count: Int { items.count }

    func image(for item: SavedSessionItem) -> NSImage? {
        NSImage(contentsOf: item.url)
    }

    var firstThumbnail: NSImage? {
        guard let first = items.first else { return nil }
        return NSImage(contentsOf: first.url)
    }

    /// The agent prompt — read from prompt.txt, or rebuilt from the items.
    var promptText: String {
        let promptURL = folder.appendingPathComponent("prompt.txt")
        if let s = try? String(contentsOf: promptURL, encoding: .utf8), !s.isEmpty {
            return s
        }
        var lines = [
            "I've highlighted regions of my screen and described the change I want for each.",
            "The screenshots are in: \(folder.path)",
            ""
        ]
        for item in items {
            lines.append("\(item.index). \(item.url.path)")
            lines.append("   \(item.displayInstruction)")
        }
        lines.append("")
        lines.append("Please open each screenshot and make the requested change.")
        return lines.joined(separator: "\n")
    }
}

/// Loads and manages saved sessions from disk.
enum SessionStore {
    private struct Manifest: Decodable {
        struct Item: Decodable {
            var index: Int
            var file: String
            var instruction: String
            var pixelWidth: Int
            var pixelHeight: Int
        }
        var createdAt: String
        var count: Int
        var items: [Item]
    }

    /// Scan the sessions root, newest first.
    static func loadAll() -> [SavedSession] {
        let fm = FileManager.default
        let root = Exporter.sessionsRoot
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sessions = entries.compactMap { load(folder: $0) }
        return sessions.sorted { $0.createdAt > $1.createdAt }
    }

    private static func load(folder: URL) -> SavedSession? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let manifestURL = folder.appendingPathComponent("cue.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return nil
        }

        let items = manifest.items.map { m in
            SavedSessionItem(
                index: m.index,
                instruction: m.instruction,
                url: folder.appendingPathComponent(m.file),
                pixelWidth: m.pixelWidth,
                pixelHeight: m.pixelHeight
            )
        }

        let created = ISO8601DateFormatter().date(from: manifest.createdAt)
            ?? (try? fm.attributesOfItem(atPath: folder.path)[.modificationDate] as? Date) as? Date
            ?? Date(timeIntervalSince1970: 0)

        return SavedSession(
            id: folder.path,
            folder: folder,
            createdAt: created,
            displayName: displayName(for: created),
            items: items
        )
    }

    static func delete(_ session: SavedSession) {
        try? FileManager.default.removeItem(at: session.folder)
    }

    private static func displayName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }
}
