import AppKit

/// One captured region within a saved session on disk.
struct SavedSessionItem: Identifiable {
    let index: Int
    let instruction: String
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int

    // Stable across reloads so the library detail rows keep their SwiftUI
    // identity (and any in-flight TextField focus / draft state) when the
    // model reloads after a save.
    var id: String { url.path }
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
    private struct Manifest: Codable {
        struct Item: Codable {
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

        guard let data = try? Data(contentsOf: manifestURL(in: folder)),
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

    /// Update the instruction for a single item inside an existing session.
    /// Rewrites the manifest, then regenerates `prompt.txt` and
    /// `instructions.md` so a subsequent "Copy Prompt" reflects the edit.
    static func updateInstruction(
        in session: SavedSession,
        atIndex itemIndex: Int,
        to newText: String
    ) throws {
        let folder = session.folder
        let url = manifestURL(in: folder)
        let data = try Data(contentsOf: url)
        var manifest = try JSONDecoder().decode(Manifest.self, from: data)

        guard let i = manifest.items.firstIndex(where: { $0.index == itemIndex }) else { return }
        if manifest.items[i].instruction == newText { return }
        manifest.items[i].instruction = newText

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: url)

        let prompt = buildPromptText(folder: folder, items: manifest.items)
        try prompt.data(using: .utf8)?.write(to: folder.appendingPathComponent("prompt.txt"))

        let markdown = buildMarkdown(folder: folder, manifest: manifest)
        try markdown.data(using: .utf8)?.write(to: folder.appendingPathComponent("instructions.md"))
    }

    // New sessions write `nudge.json`; legacy "Cue" sessions used `cue.json`.
    // Edits go back to whichever file the session was loaded from so we don't
    // orphan the legacy manifest.
    private static func manifestURL(in folder: URL) -> URL {
        let preferred = folder.appendingPathComponent("nudge.json")
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred }
        return folder.appendingPathComponent("cue.json")
    }

    private static func buildPromptText(folder: URL, items: [Manifest.Item]) -> String {
        var lines = [
            "I've highlighted regions of my screen and described the change I want for each.",
            "The screenshots are in: \(folder.path)",
            ""
        ]
        for item in items {
            let note = item.instruction.isEmpty ? "(no instruction)" : item.instruction
            lines.append("\(item.index). \(folder.appendingPathComponent(item.file).path)")
            lines.append("   \(note)")
        }
        lines.append("")
        lines.append("Please open each screenshot and make the requested change.")
        return lines.joined(separator: "\n")
    }

    private static func buildMarkdown(folder: URL, manifest: Manifest) -> String {
        let header = ISO8601DateFormatter().date(from: manifest.createdAt)
            .map(markdownStamp(_:))
            ?? manifest.createdAt
        var lines: [String] = [
            "# Nudge AI session — \(header)",
            "",
            "Each item below is a screenshot of a region and the change requested for it.",
            ""
        ]
        for item in manifest.items {
            let note = item.instruction.isEmpty ? "(no instruction)" : item.instruction
            lines.append("## \(item.index)")
            lines.append("")
            lines.append("![\(item.file)](\(item.file))")
            lines.append("")
            lines.append("- Region: \(item.pixelWidth)×\(item.pixelHeight) px")
            lines.append("- **Instruction:** \(note)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// Delete every session folder under the sessions root. Returns the number removed.
    @discardableResult
    static func clearAll() -> Int {
        let fm = FileManager.default
        let root = Exporter.sessionsRoot
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var removed = 0
        for url in entries where looksLikeSessionFolder(url) {
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }

    /// Delete session folders older than `maxAge` seconds. Returns the number removed.
    @discardableResult
    static func purge(olderThan maxAge: TimeInterval, now: Date = Date()) -> Int {
        let fm = FileManager.default
        let root = Exporter.sessionsRoot
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        let cutoff = now.addingTimeInterval(-maxAge)
        var removed = 0
        for url in entries where looksLikeSessionFolder(url) {
            let created = load(folder: url)?.createdAt
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? Date.distantFuture
            if created < cutoff, (try? fm.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }

    /// Total bytes consumed by the sessions root, recursively. 0 if the directory is missing.
    static func totalSizeOnDisk() -> Int64 {
        let fm = FileManager.default
        let root = Exporter.sessionsRoot
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static func looksLikeSessionFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        // Accept both the current "Nudge-" prefix and the legacy "Cue-" one
        // so migrated sessions stay clickable and purgeable.
        let name = url.lastPathComponent
        return name.hasPrefix("Nudge-") || name.hasPrefix("Cue-")
    }

    private static func displayName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return f.string(from: date)
    }
}

// MARK: - LibrarySession

/// Union of capture-style sessions and loop sessions; what the library lists.
enum LibrarySession: Identifiable {
    case capture(SavedSession)
    case loop(LoopSessionRecord)

    var id: String {
        switch self {
        case .capture(let s): return s.id
        case .loop(let r): return r.id
        }
    }

    var createdAt: Date {
        switch self {
        case .capture(let s): return s.createdAt
        case .loop(let r): return r.createdAt
        }
    }

    var displayName: String {
        switch self {
        case .capture(let s): return s.displayName
        case .loop(let r): return r.name
        }
    }
}

extension SessionStore {
    /// All library entries, newest first — both quick captures and loop sessions.
    static func loadAllLibrarySessions() -> [LibrarySession] {
        let captures = SessionStore.loadAll().map(LibrarySession.capture)
        let loops = LoopSessionStore.default.loadAll().map(LibrarySession.loop)
        return (captures + loops).sorted { $0.createdAt > $1.createdAt }
    }
}
