// Sources/NudgeAI/Workspace/WorkspaceWindowController.swift
import AppKit
import SwiftUI

@MainActor
final class WorkspaceWindowController {
    static let shared = WorkspaceWindowController()

    private var window: NSWindow?
    private let model = WorkspaceSessionsModel()
    private var lastUsedCwd: String?
    private var lastUsedAgentKey: String?

    func show() {
        if window == nil {
            let root = WorkspaceView(model: model, onNewSessionRequested: { [weak self] in
                self?.presentNewSessionFlow()
            })
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(contentViewController: hosting)
            win.title = "Nudge AI — Workspace"
            win.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            win.setContentSize(NSSize(width: 1100, height: 680))
            win.center()
            win.isReleasedWhenClosed = false
            self.window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Called from the menu and from library "Resume".
    func resume(record: LoopSessionRecord) {
        show()
        let cfg = AgentConfigStore.default.load()
        guard let agent = cfg.agents.first(where: { $0.key == record.agent.key })
                            ?? cfg.resolvedDefaultAgent() else {
            presentNoAgentAlert()
            return
        }
        do {
            _ = try model.resume(record: record, agent: agent)
            lastUsedCwd = record.cwd
            lastUsedAgentKey = agent.key
        } catch {
            presentSpawnFailureAlert(error: error)
        }
    }

    private func presentNewSessionFlow() {
        let cfg = AgentConfigStore.default.load()
        if cfg.agents.isEmpty {
            presentAgentConfigEditor(initial: cfg) { [weak self] saved in
                self?.openNewSessionDialog(config: saved)
            }
        } else {
            openNewSessionDialog(config: cfg)
        }
    }

    private func openNewSessionDialog(config: AgentConfigFile) {
        let host = NSHostingController(rootView: NewLoopSessionDialog(
            agents: config.agents,
            lastUsedAgentKey: lastUsedAgentKey ?? config.resolvedDefaultAgent()?.key,
            lastUsedCwd: lastUsedCwd,
            onCreate: { [weak self] name, cwd, agent in
                self?.dismissSheet()
                do {
                    _ = try self?.model.openNew(name: name, cwd: cwd, agent: agent)
                    self?.lastUsedCwd = cwd
                    self?.lastUsedAgentKey = agent.key
                } catch {
                    self?.presentSpawnFailureAlert(error: error)
                }
            },
            onCancel: { [weak self] in self?.dismissSheet() }
        ))
        presentAsSheet(host)
    }

    private func presentAgentConfigEditor(initial: AgentConfigFile, onSaved: @escaping (AgentConfigFile) -> Void) {
        let host = NSHostingController(rootView: AgentConfigEditorView(
            config: initial,
            onSave: { [weak self] saved in
                self?.dismissSheet()
                try? AgentConfigStore.default.save(saved)
                onSaved(saved)
            },
            onCancel: { [weak self] in self?.dismissSheet() }
        ))
        presentAsSheet(host)
    }

    private var sheetController: NSViewController?

    private func presentAsSheet(_ controller: NSViewController) {
        guard let window else { return }
        sheetController = controller
        window.contentViewController?.presentAsSheet(controller)
    }

    private func dismissSheet() {
        guard let parent = window?.contentViewController, let sheet = sheetController else { return }
        parent.dismiss(sheet)
        sheetController = nil
    }

    private func presentNoAgentAlert() {
        let alert = NSAlert()
        alert.messageText = "No matching agent configured"
        alert.informativeText = "This session references an agent that isn't in agents.json. Configure one to resume."
        alert.runModal()
    }

    private func presentSpawnFailureAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't start agent"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
