import Foundation

/// One-shot migration from the previous "Cue" identity to "Nudge AI".
///
/// On first launch under the new bundle id, move `~/CueSessions` to
/// `~/NudgeAISessions` (or merge its children in if both exist) so the
/// library keeps showing past sessions instead of looking suddenly empty.
enum LegacyMigration {
    static func run() {
        let fm = FileManager.default
        let legacy = Exporter.legacySessionsRoot
        let current = Exporter.sessionsRoot

        guard fm.fileExists(atPath: legacy.path) else { return }

        do {
            if !fm.fileExists(atPath: current.path) {
                try fm.moveItem(at: legacy, to: current)
            } else {
                // Both directories exist — move each child across, then drop
                // the now-empty legacy folder. We don't overwrite collisions.
                let entries = (try? fm.contentsOfDirectory(
                    at: legacy,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )) ?? []
                for src in entries {
                    let dst = current.appendingPathComponent(src.lastPathComponent)
                    if !fm.fileExists(atPath: dst.path) {
                        try? fm.moveItem(at: src, to: dst)
                    }
                }
                if (try? fm.contentsOfDirectory(atPath: legacy.path))?.isEmpty == true {
                    try? fm.removeItem(at: legacy)
                }
            }
        } catch {
            // Migration is best-effort; failures shouldn't block the app.
        }
    }
}
