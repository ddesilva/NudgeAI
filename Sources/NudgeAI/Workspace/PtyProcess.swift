// Sources/NudgeAI/Workspace/PtyProcess.swift
import Foundation
import Darwin

/// A child process (typically a shell) running in a pseudo-terminal.
/// `start` returns once the child is spawned. `onExit` fires on the main queue
/// when the child terminates. `write` and `setWindowSize` are safe to call from
/// the main thread.
final class PtyProcess {
    struct LaunchSpec {
        var executablePath: String       // e.g. "/bin/zsh"
        /// argv[1..] — `start` prepends `executablePath` as argv[0].
        var arguments: [String]
        var workingDirectory: String     // absolute
        var environment: [String: String]
    }

    private(set) var pid: pid_t = 0
    private(set) var masterFD: Int32 = -1
    var onData: ((Data) -> Void)?
    var onExit: ((Int32) -> Void)?

    private var readSource: DispatchSourceRead?
    private var waitSource: DispatchSourceProcess?

    func start(_ spec: LaunchSpec) throws {
        // forkpty: returns -1 on error, 0 in child, child PID in parent.
        var master: Int32 = 0
        let childPID = forkpty(&master, nil, nil, nil)
        guard childPID >= 0 else {
            throw NSError(domain: "PtyProcess", code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "forkpty failed: \(String(cString: strerror(errno)))"])
        }

        if childPID == 0 {
            // Child process.
            _ = chdir(spec.workingDirectory)
            for (k, v) in spec.environment {
                setenv(k, v, 1)
            }
            // Build argv[] with NULL terminator.
            let argv: [UnsafeMutablePointer<CChar>?] = ([spec.executablePath] + spec.arguments).map { strdup($0) } + [nil]
            execv(spec.executablePath, argv)
            // If execv returns, it failed; signal via _exit so atexit handlers don't run.
            _exit(127)
        }

        // Parent.
        self.pid = childPID
        self.masterFD = master

        let read = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        read.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(self.masterFD, &buf, buf.count)
            if n > 0 {
                self.onData?(Data(bytes: buf, count: n))
            } else if n == 0 {
                // EOF — child closed pty. Wait for exit below.
                read.cancel()
            } else {
                if errno != EINTR && errno != EAGAIN {
                    Log.warn("PtyProcess read error: \(String(cString: strerror(errno)))")
                    read.cancel()
                }
            }
        }
        read.activate()
        self.readSource = read

        let wait = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: .main)
        wait.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            _ = waitpid(self.pid, &status, WNOHANG)
            close(self.masterFD)
            self.masterFD = -1
            wait.cancel()
            self.onExit?(status)
        }
        wait.activate()
        self.waitSource = wait
    }

    func write(_ data: Data) {
        guard masterFD >= 0 else { return }
        data.withUnsafeBytes { buf in
            _ = Darwin.write(masterFD, buf.baseAddress, buf.count)
        }
    }

    func setWindowSize(rows: UInt16, cols: UInt16) {
        guard masterFD >= 0 else { return }
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFD, TIOCSWINSZ, &size)
    }

    func terminate() {
        guard pid > 0 else { return }
        kill(pid, SIGHUP)
    }

    deinit {
        terminate()
        if masterFD >= 0 { close(masterFD) }
    }
}
