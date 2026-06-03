import Foundation
import os

/// Writes diagnostic events to `~/Library/Logs/NudgeAI/nudgeai.log` and mirrors
/// them to the unified log so they're also visible in Console.app. The file lets
/// users grab a log off another machine without needing Console access.
enum Log {
    private static let logger = Logger(subsystem: "com.dilshan.nudgeai", category: "app")
    private static let queue = DispatchQueue(label: "com.dilshan.nudgeai.log")
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let fileURL: URL = {
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("NudgeAI", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("nudgeai.log")
    }()

    /// Wipes the previous run's log and writes a header. Call once at launch so
    /// each session is self-contained instead of accumulating forever.
    static func startNewSession() {
        queue.sync {
            let header = "==== Nudge AI launched \(iso.string(from: Date())) ====\n"
            try? header.data(using: .utf8)?.write(to: fileURL)
        }
        info("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            info("Nudge AI version \(v)")
        }
    }

    static func info(_ message: String) { write("INFO ", message); logger.info("\(message, privacy: .public)") }
    static func warn(_ message: String) { write("WARN ", message); logger.warning("\(message, privacy: .public)") }
    static func error(_ message: String) { write("ERROR", message); logger.error("\(message, privacy: .public)") }

    private static func write(_ level: String, _ message: String) {
        let line = "\(iso.string(from: Date())) \(level) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
