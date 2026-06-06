import AppKit
import Combine
import Darwin

/// One target the user can pick from the Send to picker. Could be a terminal
/// running an agent CLI (Claude Code in iTerm), a bare terminal, or an IDE/
/// chat app with its own input (Cursor, Claude Desktop).
struct AgentSession: Identifiable, Equatable {
    enum Kind: Equatable {
        case terminalAgent   // terminal running a known coding-agent CLI
        case terminal        // terminal with no agent detected
        case ide             // IDE / chat app with built-in input
    }

    let id: String
    let kind: Kind
    let appName: String       // "iTerm", "Ghostty", "Cursor"
    let bundleID: String
    let appPID: pid_t
    let agentName: String?    // "Claude Code", "Codex" — nil if no agent
    let agentPID: pid_t?
    let workingDirectory: String?
    let lastActiveAt: Date
    let agentStartedAt: Date?
    /// True when the terminal app reported this tab as its focused session
    /// (via AppleScript). Used both for ranking and for a "focused tab" badge
    /// in the picker.
    let isFocused: Bool

    /// Smart label, e.g. "Claude Code · Warp · ~/Projects/NudgeAI". App name
    /// goes in the title so the user can tell at a glance which terminal a
    /// row belongs to — the subtitle is too dim to scan quickly.
    var displayTitle: String {
        switch kind {
        case .terminalAgent:
            var parts: [String] = []
            if let agent = agentName { parts.append(agent) }
            parts.append(appName)
            if let cwd = workingDirectory { parts.append(tildify(cwd)) }
            return parts.joined(separator: " · ")
        case .terminal:
            if let cwd = workingDirectory { return "\(appName) · \(tildify(cwd))" }
            return appName
        case .ide:
            return appName
        }
    }

    var subtitle: String {
        var parts: [String] = []
        switch kind {
        case .terminalAgent:
            break
        case .terminal:
            parts.append("Any tab — paste into the front window")
        case .ide:
            parts.append("IDE / chat")
        }
        if isFocused {
            parts.append("focused tab")
        } else {
            parts.append(relativeTimeString(from: lastActiveAt))
        }
        return parts.joined(separator: " · ")
    }

    private func tildify(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func relativeTimeString(from date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 5 { return "active now" }
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86400 { return "\(Int(elapsed / 3600))h ago" }
        return "\(Int(elapsed / 86400))d ago"
    }
}

/// Catalog of apps NudgeAI knows how to target, and how to label them.
private enum AppCatalog {
    enum Match {
        case terminal(String)
        case ide(String)
    }

    /// macOS bundle IDs (with shortest unique prefix where appropriate).
    static let knownApps: [(prefix: String, match: Match)] = [
        // Terminals
        ("com.googlecode.iterm2",          .terminal("iTerm")),
        ("com.apple.Terminal",             .terminal("Terminal")),
        ("com.mitchellh.ghostty",          .terminal("Ghostty")),
        ("org.alacritty",                  .terminal("Alacritty")),
        ("net.kovidgoyal.kitty",           .terminal("kitty")),
        ("com.github.wez.wezterm",         .terminal("WezTerm")),
        ("io.tabby",                       .terminal("Tabby")),
        ("co.zeit.hyper",                  .terminal("Hyper")),

        // IDEs / chat-bearing apps
        ("com.todesktop.230313mzl4w4u92",  .ide("Cursor")),   // Cursor (todesktop)
        ("com.anthropic.claudefordesktop", .ide("Claude")),
        ("com.exafunction.windsurf",       .ide("Windsurf")),
        ("com.microsoft.VSCode",           .ide("VS Code")),
        ("com.microsoft.VSCodeInsiders",   .ide("VS Code Insiders")),
        ("com.openai.chat",                .ide("ChatGPT")),
        ("com.google.geminidesktop",       .ide("Gemini")),
    ]

    static func match(bundleID: String) -> Match? {
        for entry in knownApps where bundleID == entry.prefix || bundleID.hasPrefix(entry.prefix + ".") {
            return entry.match
        }
        return nil
    }
}

/// Known agent CLI binaries we look for in the process tree under a terminal.
private enum AgentCatalog {
    struct Signature {
        let displayName: String
        /// Basenames to compare against p_comm or the last path component.
        let binNames: Set<String>
        /// Substrings that, if present in the executable path, identify the
        /// agent. Use this for installs where p_comm is unhelpful — e.g.
        /// Claude Code's `~/.local/share/claude/versions/X.Y.Z` puts the
        /// version string in argv[0] (and therefore p_comm), so the only
        /// reliable signal is the path.
        let pathContains: [String]
    }

    static let known: [Signature] = [
        Signature(
            displayName: "Claude Code",
            binNames: ["claude", "claude-code"],
            pathContains: ["/claude/versions/", "/.local/share/claude/", "/.claude/local/"]
        ),
        Signature(displayName: "Codex",        binNames: ["codex"],        pathContains: ["/codex/versions/"]),
        Signature(displayName: "Cursor Agent", binNames: ["cursor-agent"], pathContains: []),
        Signature(displayName: "Aider",        binNames: ["aider"],        pathContains: []),
        Signature(displayName: "Gemini",       binNames: ["gemini"],       pathContains: []),
        Signature(displayName: "OpenCode",     binNames: ["opencode"],     pathContains: []),
        Signature(displayName: "Amp",          binNames: ["amp"],          pathContains: []),
        Signature(displayName: "Copilot CLI",  binNames: ["copilot"],      pathContains: []),
        Signature(displayName: "Sage",         binNames: ["sage"],         pathContains: []),
    ]

    static func match(commName: String, path: String?) -> String? {
        let comm = commName.lowercased()
        let lowerPath = path?.lowercased()
        let lastComponent = path.map { ($0 as NSString).lastPathComponent.lowercased() }

        for sig in known {
            if sig.binNames.contains(comm) { return sig.displayName }
            if let last = lastComponent, sig.binNames.contains(last) { return sig.displayName }
            if let lp = lowerPath, sig.pathContains.contains(where: { lp.contains($0) }) {
                return sig.displayName
            }
        }
        return nil
    }
}

/// Detects active agent sessions on the Mac and keeps a recency map of which
/// apps the user has most recently focused.
@MainActor
final class AgentSessionDetector: ObservableObject {
    static let shared = AgentSessionDetector()

    @Published private(set) var sessions: [AgentSession] = []

    /// Per-bundle "last frontmost" observations. Seeds from current frontmost
    /// app at init; updates whenever the active app changes.
    private var lastFrontmostByBundle: [String: Date] = [:]
    /// Last-known focused tty per terminal app, refreshed on a background
    /// queue so the AppleScript round-trip (and any first-time TCC permission
    /// prompt) never blocks the main thread.
    private var cachedFocusedTTYs: [String: String] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private let probeQueue = DispatchQueue(label: "com.dilshan.nudgeai.terminal-focus-probe", qos: .userInitiated)
    private var probeInFlight = false

    private init() {
        installFrontmostObserver()
    }

    deinit {
        let nc = NSWorkspace.shared.notificationCenter
        for o in workspaceObservers { nc.removeObserver(o) }
    }

    /// Fast synchronous rescan that republishes `sessions` immediately using
    /// the last-known focused-tty map, then kicks off an asynchronous probe of
    /// the terminal apps to refresh that map. The probe can block on TCC
    /// permission prompts or slow AppleScript replies, so it MUST not run on
    /// the main thread — that's what previously caused the beachball.
    func refresh() {
        sessions = ProcessScanner.computeSessions(
            lastFrontmostByBundle: lastFrontmostByBundle,
            focusedTTYByBundle: cachedFocusedTTYs
        )

        // Snapshot the inputs the background probe needs before hopping off
        // the main actor (NSRunningApplication is main-thread-only to read).
        let candidates: [(bid: String, source: String)] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bid = app.bundleIdentifier,
                  let src = TerminalFocusProbe.scripts[bid] else { return nil }
            return (bid, src)
        }
        guard !candidates.isEmpty, !probeInFlight else { return }
        probeInFlight = true

        probeQueue.async { [weak self] in
            let focused = TerminalFocusProbe.run(candidates: candidates)
            DispatchQueue.main.async {
                guard let self else { return }
                self.probeInFlight = false
                guard focused != self.cachedFocusedTTYs else { return }
                self.cachedFocusedTTYs = focused
                self.sessions = ProcessScanner.computeSessions(
                    lastFrontmostByBundle: self.lastFrontmostByBundle,
                    focusedTTYByBundle: focused
                )
            }
        }
    }

    private func installFrontmostObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        let obs = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bid = app.bundleIdentifier else { return }
            // `queue: .main` means we're already on the main thread, but the
            // closure isn't marked @MainActor. Hop explicitly so Swift's
            // concurrency model is satisfied.
            MainActor.assumeIsolated {
                self?.lastFrontmostByBundle[bid] = Date()
            }
        }
        workspaceObservers.append(obs)
        if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            lastFrontmostByBundle[bid] = Date()
        }
    }
}

// MARK: - Focused-tab probe

/// Asks supported terminal apps which session is currently focused, via
/// AppleScript. Requires the user to have granted Automation permission for
/// Nudge AI → terminal (macOS prompts on first attempt). Returns nil for any
/// app it can't talk to (denied, not running, script error) — callers fall
/// back to tty-activity ranking.
///
/// IMPORTANT: `run(candidates:)` must NOT be called on the main thread. The
/// first invocation triggers a synchronous TCC prompt that can block for
/// many seconds; blocking the main thread there both freezes the UI and
/// hides the prompt behind any `.floating` window we already showed.
enum TerminalFocusProbe {
    /// Bundle ID → AppleScript source that returns the tty path of the
    /// currently focused session (e.g. "/dev/ttys004").
    static let scripts: [String: String] = [
        "com.googlecode.iterm2": #"tell application id "com.googlecode.iterm2" to tty of current session of current window"#,
        "com.apple.Terminal":    #"tell application id "com.apple.Terminal" to tty of selected tab of front window"#,
    ]

    /// Background-thread entrypoint. Pre-snapshot the bundle/source pairs on
    /// the main thread and hand them here.
    nonisolated static func run(candidates: [(bid: String, source: String)]) -> [String: String] {
        var out: [String: String] = [:]
        for c in candidates {
            if let tty = execute(c.source) { out[c.bid] = tty }
        }
        return out
    }

    private nonisolated static func execute(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errInfo: NSDictionary?
        let result = script.executeAndReturnError(&errInfo)
        if errInfo != nil { return nil }
        let s = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }
}

// MARK: - Process scanning (nonisolated, pure-input)

private enum ProcessScanner {
    struct ProcInfo {
        let pid: pid_t
        let ppid: pid_t
        let name: String     // p_comm (truncated to ~16 chars)
        let path: String?    // proc_pidpath result, if available
        let startTime: Date?
        let tdev: dev_t      // controlling-tty device id, or NODEV (~0)
    }

    static func computeSessions(
        lastFrontmostByBundle: [String: Date],
        focusedTTYByBundle: [String: String] = [:]
    ) -> [AgentSession] {
        let procs = enumerate()
        var byPID: [pid_t: ProcInfo] = [:]
        var childrenByPPID: [pid_t: [pid_t]] = [:]
        for p in procs {
            byPID[p.pid] = p
            childrenByPPID[p.ppid, default: []].append(p.pid)
        }

        let runningApps = NSWorkspace.shared.runningApplications
        var out: [AgentSession] = []

        for app in runningApps {
            guard let bid = app.bundleIdentifier,
                  let match = AppCatalog.match(bundleID: bid) else { continue }

            let appPID = app.processIdentifier
            let lastFront = lastFrontmostByBundle[bid] ?? app.launchDate ?? Date.distantPast

            switch match {
            case .ide(let displayName):
                out.append(AgentSession(
                    id: "ide-\(appPID)",
                    kind: .ide,
                    appName: displayName,
                    bundleID: bid,
                    appPID: appPID,
                    agentName: nil,
                    agentPID: nil,
                    workingDirectory: nil,
                    lastActiveAt: lastFront,
                    agentStartedAt: nil,
                    isFocused: false
                ))

            case .terminal(let displayName):
                let descendants = collectDescendants(of: appPID, childrenByPPID: childrenByPPID)
                let agentMatches = descendants.compactMap { pid -> (pid_t, String)? in
                    guard let info = byPID[pid] else { return nil }
                    if let agent = AgentCatalog.match(commName: info.name, path: info.path) {
                        return (pid, agent)
                    }
                    return nil
                }

                // If we know the focused tty for this terminal app, that's
                // the authoritative "user's last-interacted tab" signal —
                // a session whose tty matches it wins regardless of tty
                // activity.
                let focusedTTY = focusedTTYByBundle[bid]
                let focusedDev: dev_t? = focusedTTY.flatMap { devForTTYPath($0) }
                let focusBoost = Date.distantFuture

                var ttyActivityByDev: [dev_t: Date] = [:]
                for (pid, agentName) in agentMatches {
                    let cwd = cwd(forPID: pid)
                    let start = byPID[pid]?.startTime
                    let tdev = byPID[pid]?.tdev ?? dev_t(bitPattern: ~0)
                    let ttyAct: Date? = {
                        if let cached = ttyActivityByDev[tdev] { return cached }
                        let v = ttyActivity(tdev: tdev)
                        if let v { ttyActivityByDev[tdev] = v }
                        return v
                    }()
                    let isFocused = (focusedDev != nil && tdev == focusedDev)
                    // Focused tab → pin to top. Otherwise prefer the tty's
                    // last read/write; fall back to agent start / frontmost.
                    let activity: Date = isFocused
                        ? focusBoost
                        : (ttyAct ?? max(lastFront, start ?? Date.distantPast))
                    out.append(AgentSession(
                        id: "agent-\(pid)",
                        kind: .terminalAgent,
                        appName: displayName,
                        bundleID: bid,
                        appPID: appPID,
                        agentName: agentName,
                        agentPID: pid,
                        workingDirectory: cwd,
                        lastActiveAt: activity,
                        agentStartedAt: start,
                        isFocused: isFocused
                    ))
                }

                // Always emit one bare ".terminal" entry per running terminal
                // app so non-agent tabs (e.g. a Warp tab running just a shell)
                // still appear as a send target. We can't focus a specific tab
                // from outside, so this represents "the front tab of this app".
                // tdevs that already host an agent are excluded — those are
                // surfaced as their own entries above.
                let nodev = dev_t(bitPattern: ~0)
                let agentTDevs: Set<dev_t> = Set(agentMatches.compactMap { byPID[$0.0]?.tdev })
                let bareShells: [(pid: pid_t, tdev: dev_t)] = descendants.compactMap { pid in
                    guard let info = byPID[pid], info.tdev != nodev, info.tdev != 0 else { return nil }
                    if agentTDevs.contains(info.tdev) { return nil }
                    return (pid, info.tdev)
                }
                let focusedBareShell: (pid: pid_t, tdev: dev_t)? = focusedDev.flatMap { fd in
                    bareShells.first(where: { $0.tdev == fd })
                }
                let bestBareShell: (pid: pid_t, tdev: dev_t)? = focusedBareShell ?? bareShells.max { l, r in
                    let lt = ttyActivityByDev[l.tdev] ?? ttyActivity(tdev: l.tdev) ?? Date.distantPast
                    let rt = ttyActivityByDev[r.tdev] ?? ttyActivity(tdev: r.tdev) ?? Date.distantPast
                    return lt < rt
                }
                let bareCwd = bestBareShell.flatMap { cwd(forPID: $0.pid) }
                let bareIsFocused = focusedBareShell != nil
                let bareActivity: Date = {
                    if bareIsFocused { return focusBoost }
                    if let s = bestBareShell, let act = ttyActivity(tdev: s.tdev) {
                        return max(act, lastFront)
                    }
                    return lastFront
                }()
                out.append(AgentSession(
                    id: "terminal-\(appPID)",
                    kind: .terminal,
                    appName: displayName,
                    bundleID: bid,
                    appPID: appPID,
                    agentName: nil,
                    agentPID: nil,
                    workingDirectory: bareCwd,
                    lastActiveAt: bareActivity,
                    agentStartedAt: nil,
                    isFocused: bareIsFocused
                ))
            }
        }

        // Bare ".terminal" rows are catch-alls ("any tab — paste into the
        // front window") — they're only useful when none of the specific
        // agent rows are what the user wants. Sink them below every agent
        // or IDE entry; within bare rows, keep the activity-based order.
        out.sort { a, b in
            let aBare = a.kind == .terminal
            let bBare = b.kind == .terminal
            if aBare != bBare { return !aBare }
            return a.lastActiveAt > b.lastActiveAt
        }
        return out
    }

    private static func collectDescendants(of root: pid_t, childrenByPPID: [pid_t: [pid_t]]) -> [pid_t] {
        var result: [pid_t] = []
        var stack: [pid_t] = [root]
        var seen: Set<pid_t> = [root]
        while let pid = stack.popLast() {
            for child in childrenByPPID[pid] ?? [] where !seen.contains(child) {
                seen.insert(child)
                result.append(child)
                stack.append(child)
            }
        }
        return result
    }

    // MARK: BSD process enumeration via sysctl

    private static func enumerate() -> [ProcInfo] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: size_t = 0
        if sysctl(&mib, 4, nil, &size, nil, 0) != 0 { return [] }
        guard size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 1)
        if sysctl(&mib, 4, &buffer, &size, nil, 0) != 0 { return [] }
        let count = size / stride

        var out: [ProcInfo] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            var proc = buffer[i]
            let pid = proc.kp_proc.p_pid
            let ppid = proc.kp_eproc.e_ppid
            guard pid > 0 else { continue }

            // p_comm is a fixed-size C array; rebind to read as a cString.
            let name = withUnsafePointer(to: &proc.kp_proc.p_comm) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }

            let path = procPath(pid: pid)
            let start = procStartTime(pid: pid)
            let tdev = proc.kp_eproc.e_tdev

            out.append(ProcInfo(pid: pid, ppid: ppid, name: name, path: path, startTime: start, tdev: tdev))
        }
        return out
    }

    private static func procStartTime(pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let n = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, ptr, size)
        }
        if Int(n) < MemoryLayout<proc_bsdinfo>.size { return nil }
        let sec = TimeInterval(info.pbi_start_tvsec)
        let usec = TimeInterval(info.pbi_start_tvusec) / 1_000_000
        guard sec > 0 else { return nil }
        return Date(timeIntervalSince1970: sec + usec)
    }

    private static func procPath(pid: pid_t) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE is `(4 * MAXPATHLEN)` in <sys/proc_info.h>,
        // but the macro is unavailable to Swift. Inline the same value.
        let cap = 4 * Int(MAXPATHLEN)
        var buf = [CChar](repeating: 0, count: cap)
        let n = proc_pidpath(pid, &buf, UInt32(cap))
        if n <= 0 { return nil }
        return String(cString: buf)
    }

    /// Resolves a tty path like "/dev/ttys004" back to a dev_t so we can
    /// compare it against `kp_eproc.e_tdev`.
    static func devForTTYPath(_ path: String) -> dev_t? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return st.st_rdev
    }

    /// Most recent read or write on the agent's controlling tty. Useful as
    /// a fallback rank when we can't ask the terminal which tab is focused —
    /// every keystroke echoes back as a write, every scroll/redraw bumps
    /// mtime, every prompt read bumps atime. Returns nil for daemons or
    /// processes without a controlling tty.
    static func ttyActivity(tdev: dev_t) -> Date? {
        guard tdev != dev_t(bitPattern: ~0), tdev != 0 else { return nil }
        guard let cstr = devname(tdev, S_IFCHR) else { return nil }
        let path = "/dev/" + String(cString: cstr)
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        let m = TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1_000_000_000
        let a = TimeInterval(st.st_atimespec.tv_sec) + TimeInterval(st.st_atimespec.tv_nsec) / 1_000_000_000
        return Date(timeIntervalSince1970: max(m, a))
    }

    private static func cwd(forPID pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let n = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
            proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, ptr, size)
        }
        if Int(n) < MemoryLayout<proc_vnodepathinfo>.size { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { ptr -> String? in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                let s = String(cString: $0)
                return s.isEmpty ? nil : s
            }
        }
    }
}
