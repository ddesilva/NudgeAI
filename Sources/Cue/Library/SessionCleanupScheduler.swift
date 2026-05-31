import AppKit

/// Periodically purges session folders older than `maxAge` from disk.
/// Runs once shortly after launch and then on a recurring interval.
@MainActor
final class SessionCleanupScheduler {
    private let maxAge: TimeInterval
    private let interval: TimeInterval
    private var timer: Timer?

    init(maxAge: TimeInterval = SessionStore.defaultMaxAge,
         interval: TimeInterval = 6 * 60 * 60) {
        self.maxAge = maxAge
        self.interval = interval
    }

    func start() {
        // First sweep shortly after launch so it doesn't compete with UI setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.sweep()
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sweep() {
        let removed = SessionStore.purge(olderThan: maxAge)
        if removed > 0 {
            NotificationCenter.default.post(name: .cueSessionsChanged, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted whenever the on-disk session set has changed (auto-purge or manual clear).
    static let cueSessionsChanged = Notification.Name("CueSessionsChanged")
}
