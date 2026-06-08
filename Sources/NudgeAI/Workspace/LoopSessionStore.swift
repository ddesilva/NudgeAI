import Foundation

/// Reads/writes loop sessions under `root` (defaults to `Exporter.sessionsRoot`).
struct LoopSessionStore {
    static var `default`: LoopSessionStore { LoopSessionStore(root: Exporter.sessionsRoot) }

    let root: URL

    func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    func manifestURL(for id: String) -> URL {
        folder(for: id).appendingPathComponent("session.json")
    }

    func save(_ rec: LoopSessionRecord) throws {
        let dir = folder(for: rec.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder.loopSessionEncoder.encode(rec)
        try data.write(to: manifestURL(for: rec.id), options: [.atomic])
    }

    func load(id: String) throws -> LoopSessionRecord {
        let data = try Data(contentsOf: manifestURL(for: id))
        return try JSONDecoder.loopSessionDecoder.decode(LoopSessionRecord.self, from: data)
    }

    /// All loop sessions on disk, newest `createdAt` first. Silently skips folders
    /// that don't parse — they're surfaced via Log in a follow-up commit.
    func loadAll() -> [LoopSessionRecord] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let candidates = entries.filter { $0.lastPathComponent.hasPrefix("loop-") }
        let records = candidates.compactMap { try? load(id: $0.lastPathComponent) }
        return records.sorted { $0.createdAt > $1.createdAt }
    }

    /// `loop-<yyyyMMddHHmmss>-<slug>` — sortable by timestamp prefix, slug derived from name.
    static func newSessionID(name: String, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        let stamp = f.string(from: now)
        let slug = slugify(name)
        return "loop-\(stamp)-\(slug)"
    }

    private static func slugify(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "session" : collapsed
    }
}
