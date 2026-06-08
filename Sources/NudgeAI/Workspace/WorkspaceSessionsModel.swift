// Sources/NudgeAI/Workspace/WorkspaceSessionsModel.swift
import Foundation
import Combine

@MainActor
final class WorkspaceSessionsModel: ObservableObject {
    @Published var sessions: [WorkspaceSession] = []
    @Published var activeID: String?

    var active: WorkspaceSession? {
        sessions.first { $0.id == activeID }
    }

    /// Create a brand-new loop session, persist it, spawn the pty, and activate.
    func openNew(name: String, cwd: String, agent: AgentConfigFile.Agent) throws -> WorkspaceSession {
        let now = Date()
        let rec = LoopSessionRecord(
            id: LoopSessionStore.newSessionID(name: name, now: now),
            name: name,
            cwd: cwd,
            agent: .init(key: agent.key, binary: agent.binary),
            createdAt: now,
            lastActiveAt: now,
            status: .open,
            previewURL: nil
        )
        try LoopSessionStore.default.save(rec)
        let session = WorkspaceSession(record: rec)
        try session.launch(agent: agent)
        sessions.append(session)
        activeID = session.id
        return session
    }

    /// Resume a session that already exists on disk — spawn a fresh pty.
    func resume(record: LoopSessionRecord, agent: AgentConfigFile.Agent) throws -> WorkspaceSession {
        if let existing = sessions.first(where: { $0.id == record.id }) {
            activeID = existing.id
            return existing
        }
        var updated = record
        updated.status = .open
        updated.lastActiveAt = Date()
        try LoopSessionStore.default.save(updated)
        let session = WorkspaceSession(record: updated)
        try session.launch(agent: agent)
        sessions.append(session)
        activeID = session.id
        return session
    }

    /// Close a tab. Persists `status=closed` and terminates the pty.
    func close(_ session: WorkspaceSession) {
        session.pty.terminate()
        var rec = session.record
        rec.close(at: Date())
        try? LoopSessionStore.default.save(rec)
        sessions.removeAll { $0.id == session.id }
        if activeID == session.id {
            activeID = sessions.first?.id
        }
    }
}
