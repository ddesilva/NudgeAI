// Sources/NudgeAI/Workspace/WorkspaceSession.swift
import Foundation
import Combine

/// One workspace tab's runtime state. Outlives the SwiftUI view tree so the
/// pty doesn't die when the user switches tabs.
@MainActor
final class WorkspaceSession: ObservableObject, Identifiable {
    let id: String
    @Published var record: LoopSessionRecord
    let pty: PtyProcess
    @Published var ptyExitCode: Int32?

    init(record: LoopSessionRecord) {
        self.id = record.id
        self.record = record
        self.pty = PtyProcess()
        pty.onExit = { [weak self] code in
            self?.ptyExitCode = code
        }
    }

    /// Spawns the shell + auto-runs the agent command.
    func launch(agent: AgentConfigFile.Agent) throws {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Build a shell invocation that auto-runs the agent then drops back to
        // an interactive shell, so ⌃C lands the user at $SHELL instead of
        // killing the pty.
        let agentInvocation = ([agent.binary] + agent.args)
            .map { shellQuote($0) }
            .joined(separator: " ")
        let initCmd = "\(agentInvocation); exec \(shell) -l"

        var env = ProcessInfo.processInfo.environment
        env["NUDGEAI_SESSION_ID"] = record.id
        env["NUDGEAI_SESSION_NAME"] = record.name
        // NUDGEAI_MCP_SOCKET is added in v0.3.
        if let agentEnv = agent.env {
            for (k, v) in agentEnv { env[k] = v }
        }

        try pty.start(.init(
            executablePath: shell,
            arguments: ["-l", "-c", initCmd],     // argv[1..]; PtyProcess adds shell as argv[0]
            workingDirectory: record.cwd,
            environment: env
        ))
    }

    private func shellQuote(_ s: String) -> String {
        // POSIX single-quote with embedded single-quote escape.
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
