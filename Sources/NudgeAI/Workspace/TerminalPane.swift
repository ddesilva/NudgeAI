// Sources/NudgeAI/Workspace/TerminalPane.swift
import SwiftUI
import AppKit
import SwiftTerm

/// SwiftUI wrapper around SwiftTerm's `TerminalView`, bridged to a `PtyProcess`.
struct TerminalPane: NSViewRepresentable {
    @ObservedObject var session: WorkspaceSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.terminalDelegate = context.coordinator
        view.feed(text: "\u{001B}[2J\u{001B}[H")   // clear, home
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        // Currently no React-style state to push; SwiftTerm owns its scrollback.
    }

    @MainActor
    final class Coordinator: NSObject, TerminalViewDelegate {
        let session: WorkspaceSession
        private weak var view: TerminalView?

        init(session: WorkspaceSession) {
            self.session = session
        }

        func attach(to view: TerminalView) {
            self.view = view
            session.pty.onData = { [weak view] data in
                guard let view else { return }
                view.feed(byteArray: [UInt8](data)[...])
            }
            session.pty.onExit = { [weak self] code in
                self?.view?.feed(text: "\r\n[process exited with code \(code)]\r\n")
            }
        }

        // MARK: TerminalViewDelegate

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            session.pty.write(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            session.pty.setWindowSize(rows: UInt16(newRows), cols: UInt16(newCols))
        }

        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func clipboardCopy(source: TerminalView, content: Data) {
            if let s = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
            }
        }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func bell(source: TerminalView) { NSSound.beep() }
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
        }
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

