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
    /// 0…1 normalized RMS of the live mic buffer while listening, 0 otherwise.
    /// Drives the audio-reactive glow on `MicButton` so the UI visibly
    /// responds to the user's voice — silence is faint, speech is bright.
    @Published private(set) var audioLevel: Float = 0

    private let recognizer: SFSpeechRecognizer?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Accumulates finalized segments within one listening session.
    /// `SFSpeechRecognizer` (especially on-device) auto-finalizes on silence,
    /// after which subsequent partials' `bestTranscription` cover only the new
    /// utterance — not the cumulative transcript. Without stitching, a pause
    /// mid-dictation would let the next partial wipe the earlier text via
    /// `MicButton.applyPartial`'s range-replace.
    private var finalizedTranscript: String = ""

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
        audioLevel = 0
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
        finalizedTranscript = ""
        audioLevel = 0
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
        // Audio tap runs on a real-time audio thread. RMS computation is cheap
        // (a few thousand multiplies per ~21 ms buffer at 48 kHz / 1024 frames);
        // hopping to MainActor each buffer to update `audioLevel` is ~47 Hz,
        // which SwiftUI animates smoothly via the easing on the consumer side.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.normalizedRMS(of: buffer)
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
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
                    self.absorb(result: result)
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
        self.finalizedTranscript = ""
        state = .listening
    }

    /// Fold the latest recognition result into a monotonically-growing partial.
    /// On silence-induced auto-finalization the recognizer can emit new
    /// partials whose `bestTranscription` covers only the new utterance; the
    /// `hasPrefix` check tolerates the alternative cumulative behavior so we
    /// don't double-prepend.
    private func absorb(result: SFSpeechRecognitionResult) {
        let current = result.bestTranscription.formattedString
        let combined: String
        if finalizedTranscript.isEmpty {
            combined = current
        } else if current.hasPrefix(finalizedTranscript) {
            combined = current
        } else {
            combined = finalizedTranscript + " " + current
        }
        partial = combined
        if result.isFinal {
            finalizedTranscript = combined
        }
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

    /// Root-mean-square of one buffer, scaled into a roughly UI-friendly 0…1
    /// range. Typical conversational voice peaks near rms ≈ 0.1–0.15; an 8×
    /// gain pushes that to ≈0.8–1.2 which we clamp.
    private static func normalizedRMS(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sumSquares: Float = 0
        for i in 0..<n {
            let sample = data[i]
            sumSquares += sample * sample
        }
        let rms = sqrt(sumSquares / Float(n))
        return min(1.0, rms * 8.0)
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
