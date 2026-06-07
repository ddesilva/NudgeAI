import AppKit
import Combine

/// Orchestrates a capture session: overlay → capture → instruction → repeat,
/// then review & export.
@MainActor
final class SessionController: ObservableObject {
    @Published var annotations: [Annotation] = []
    private(set) var isActive = false

    weak var menuBar: MenuBarController?

    private let overlay = SelectionOverlayController()
    private let instruction = InstructionPanelController()
    private let control = FloatingControlController()
    private var reviewWindow: ReviewWindowController?
    private var sendPicker: SendToPickerController?

    private let autoRearm = true

    // MARK: Session lifecycle

    func startSession() {
        guard !isActive else { return }
        guard ensurePermission() else { return }
        annotations.removeAll()
        isActive = true
        menuBar?.rebuildMenu()
        showControl()       // persistent HUD for the whole session
        beginCapture()
    }

    func beginCapture() {
        guard isActive else { return }
        // Keep the HUD up — it floats above the overlay so Done stays clickable.
        instruction.close()
        overlay.onSelect = { [weak self] rect in self?.handleSelection(rect) }
        // Escape from the overlay exits the session: review what's already been
        // captured, or cancel outright if nothing has been captured yet so the
        // user isn't dumped into a stalled session with no overlay.
        overlay.onCancel = { [weak self] in
            guard let self else { return }
            if self.annotations.isEmpty {
                self.cancelSession()
            } else {
                self.endSession()
            }
        }
        overlay.show()
    }

    func endSession() {
        guard isActive else { return }
        overlay.close()
        instruction.close()
        control.close()
        isActive = false
        menuBar?.rebuildMenu()

        guard !annotations.isEmpty else { return }
        let controller = ReviewWindowController(session: self)
        reviewWindow = controller
        controller.show()
    }

    /// Close the session and export+copy the prompt without showing the
    /// review window. Used by Save & Done when there's nothing worth reviewing.
    private func finishSessionAndExport() {
        overlay.close()
        instruction.close()
        control.close()
        isActive = false
        menuBar?.rebuildMenu()

        guard !annotations.isEmpty else { return }
        do {
            let result = try Exporter.export(annotations: annotations)
            Exporter.copyPromptToClipboard(result.promptForAgent)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        annotations.removeAll()
    }

    /// Like `finishSessionAndExport`, but also surfaces the saved session in
    /// the Sessions library so the user lands on their history after Done.
    private func finishSessionAndShowLibrary() {
        finishSessionAndExport()
        LibraryWindowController.shared.show()
    }

    /// Same as `finishSessionAndExport`, but instead of just copying the
    /// prompt, opens the Send to picker so the user can deliver it to an
    /// active agent session. Used by Send to from the instruction panel.
    private func finishSessionAndSendTo() {
        overlay.close()
        instruction.close()
        control.close()
        isActive = false
        menuBar?.rebuildMenu()

        guard !annotations.isEmpty else { return }
        let exportResult: Exporter.Result
        do {
            exportResult = try Exporter.export(annotations: annotations)
        } catch {
            NSAlert(error: error).runModal()
            annotations.removeAll()
            return
        }

        let prompt = exportResult.promptForAgent
        let picker = SendToPickerController()
        sendPicker = picker
        picker.present(host: nil) { [weak self] target in
            self?.sendPicker = nil
            let chosen = target ?? .clipboard
            _ = SendDispatcher.send(prompt: prompt, to: chosen)
        }
        annotations.removeAll()
    }

    func cancelSession() {
        overlay.close()
        instruction.close()
        control.close()
        annotations.removeAll()
        isActive = false
        menuBar?.rebuildMenu()
    }

    // MARK: Capture flow

    private func handleSelection(_ rect: NSRect) {
        overlay.close()
        guard let result = CaptureService.capture(appKitRect: rect) else {
            presentCaptureFailure()
            return
        }
        let sizeLabel = "\(Int(result.pixelSize.width))×\(Int(result.pixelSize.height)) px"
        instruction.onCommit = { [weak self] text in
            self?.addAnnotation(image: result.image, pixelSize: result.pixelSize, rect: rect, text: text)
        }
        instruction.onCommitAndFinish = { [weak self] text in
            guard let self else { return }
            self.addAnnotation(
                image: result.image, pixelSize: result.pixelSize,
                rect: rect, text: text, rearm: false
            )
            // Copy to Clipboard is only shown on the first box, so the
            // session is always single-capture here: export & copy without
            // dropping into the review window.
            self.finishSessionAndExport()
        }
        instruction.onCommitAndDone = { [weak self] text in
            guard let self else { return }
            self.addAnnotation(
                image: result.image, pixelSize: result.pixelSize,
                rect: rect, text: text, rearm: false
            )
            // Done is shown from the 2nd capture onward: finalise on disk
            // and open the Sessions library so the user can see the full
            // list of screenshots and instructions they just built.
            self.finishSessionAndShowLibrary()
        }
        instruction.onCommitAndSendTo = { [weak self] text in
            guard let self else { return }
            self.addAnnotation(
                image: result.image, pixelSize: result.pixelSize,
                rect: rect, text: text, rearm: false
            )
            self.finishSessionAndSendTo()
        }
        // Cancelling a single box drops the panel and re-arms the overlay,
        // so the user is back in select mode immediately instead of being
        // stranded with just the HUD.
        instruction.onCancel = { [weak self] in self?.beginCapture() }
        instruction.show(
            thumbnail: result.image,
            anchorRect: rect,
            index: annotations.count + 1,
            sizeLabel: sizeLabel
        )
    }

    private func addAnnotation(image: NSImage, pixelSize: CGSize, rect: NSRect, text: String, rearm: Bool = true) {
        let annotation = Annotation(
            image: image,
            instruction: text,
            rect: rect,
            pixelSize: pixelSize,
            createdAt: Date()
        )
        annotations.append(annotation)
        menuBar?.rebuildMenu()
        control.updateCount(annotations.count)

        if rearm && autoRearm {
            beginCapture()
        }
    }

    private func showControl() {
        control.onAddBox = { [weak self] in self?.beginCapture() }
        control.onDone = { [weak self] in self?.endSession() }
        control.onCancel = { [weak self] in self?.cancelSession() }
        control.show(count: annotations.count)
    }

    // MARK: Helpers

    private func ensurePermission() -> Bool {
        if CaptureService.hasPermission() { return true }
        CaptureService.requestPermission()
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        Nudge AI needs Screen Recording access to capture the regions you highlight.

        Open System Settings ▸ Privacy & Security ▸ Screen Recording, enable Nudge AI, \
        then start a session again. You may need to quit and reopen Nudge AI after granting access.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        return false
    }

    private func presentCaptureFailure() {
        let alert = NSAlert()
        alert.messageText = "Couldn't capture that region"
        alert.informativeText = "The capture returned no image. Make sure Screen Recording is enabled for Nudge AI and try again."
        alert.runModal()
    }

    func closeReview() {
        reviewWindow = nil
    }
}
