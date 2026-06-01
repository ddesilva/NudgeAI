import AppKit

/// Periodically purges session folders older than the user's configured
/// retention from disk. Runs once shortly after launch, then on a recurring
/// interval, and again whenever preferences change.
@MainActor
final class SessionCleanupScheduler {
    private let interval: TimeInterval
    private var timer: Timer?
    private var prefsObserver: NSObjectProtocol?

    init(interval: TimeInterval = 6 * 60 * 60) {
        self.interval = interval
    }

    deinit {
        if let prefsObserver { NotificationCenter.default.removeObserver(prefsObserver) }
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

        // Re-sweep immediately when the retention setting changes so a shorter
        // window takes effect right away.
        prefsObserver = NotificationCenter.default.addObserver(
            forName: .nudgePreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let prefsObserver {
            NotificationCenter.default.removeObserver(prefsObserver)
            self.prefsObserver = nil
        }
    }

    private func sweep() {
        let removed = SessionStore.purge(olderThan: Preferences.retentionMaxAge)
        if removed > 0 {
            NotificationCenter.default.post(name: .nudgeSessionsChanged, object: nil)
        }
    }
}

extension Notification.Name {
    /// Posted whenever the on-disk session set has changed (auto-purge or manual clear).
    static let nudgeSessionsChanged = Notification.Name("NudgeSessionsChanged")
}
