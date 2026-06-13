import Foundation
import Speech
import AVFoundation
import Combine

/// One dictation session backed by `SFSpeechRecognizer` + `AVAudioEngine`.
/// Owned per `MicButton` as a `@StateObject`; tears down on view removal.
@MainActor
final class SpeechDictation: ObservableObject {
    enum DenyReason: String, Equatable {
        case microphone
        case speech
    }

    enum State: Equatable {
        case idle
        case preparing
        case listening
        case denied(DenyReason)
        case failed(String)
        /// macOS Dictation is turned off in System Settings → Keyboard, which
        /// `SFSpeechRecognizer` requires to function at all. Distinct from a
        /// permission deny — the user has to enable a *feature*, not grant
        /// access.
        case dictationOff
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var partial: String = ""

    private let recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = .autoupdatingCurrent) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    deinit {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        task?.cancel()
    }

    /// Idempotent. Lazy-asks for mic + speech permission on first call; on
    /// subsequent calls the cached grant short-circuits straight to listening.
    func start() {
        switch state {
        case .preparing, .listening:
            return
        default:
            break
        }
        state = .preparing

        Task { [weak self] in
            guard let self else { return }
            let micGranted = await Self.requestMicPermission()
            guard micGranted else {
                await MainActor.run { self.state = .denied(.microphone) }
                return
            }
            let speechGranted = await Self.requestSpeechPermission()
            guard speechGranted else {
                await MainActor.run { self.state = .denied(.speech) }
                return
            }
            await MainActor.run { self.beginListening() }
        }
    }

    /// Stop the session, treat the last partial as final.
    func stop() {
        guard case .listening = state else { return }
        tearDownStream()
        state = .idle
    }

    /// Abort the session without committing. Caller may then revert text.
    func cancel() {
        switch state {
        case .listening, .preparing:
            tearDownStream()
        default:
            break
        }
        partial = ""
        state = .idle
    }

    private func tearDownStream() {
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        engine = nil
        request = nil
        task = nil
    }

    private func beginListening() {
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognizer is unavailable for the current locale.")
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            state = .failed(error.localizedDescription)
            return
        }

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.partial = result.bestTranscription.formattedString
                }
                if let error {
                    Log.warn("SpeechDictation task error: \(error.localizedDescription)")
                    self.state = Self.classify(error)
                    self.tearDownStream()
                }
            }
        }

        self.engine = engine
        self.request = request
        self.task = task
        self.partial = ""
        state = .listening
    }

    /// Maps a raw recognition error into the most specific `State` we can.
    /// "Siri and Dictation are disabled" comes back from macOS when the system
    /// Dictation feature is off — distinct from a denied permission.
    private static func classify(_ error: Error) -> State {
        let message = error.localizedDescription
        let lower = message.lowercased()
        if lower.contains("dictation") || lower.contains("siri") {
            return .dictationOff
        }
        return .failed(message)
    }

    private static func requestMicPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private static func requestSpeechPermission() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
        default: return false
        }
    }
}
