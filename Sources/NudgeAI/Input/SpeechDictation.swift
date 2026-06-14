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
        /// User tapped the mic mid-session to suspend it. The audio stream and
        /// recognition task are torn down (so nothing records), but the text
        /// dictated so far is left in the field and the next tap resumes,
        /// appending from the cursor. Drawn with an orange ring.
        case paused
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
    /// Smoothed 0…1 FFT band magnitudes (low→high frequency) while listening,
    /// zeros otherwise. Drives `VoiceEqualizerView`. Fast-attack/slow-release
    /// so bars rise instantly with speech but fall back gently.
    @Published private(set) var spectrum: [Float] = [Float](repeating: 0, count: 64)

    private let bandCount = 64
    /// Per-frame decay applied to the previous band value on release. Lower =
    /// snappier fall back to baseline once speech stops (tuned for a quick but
    /// not jittery return to the 0 state at the ~47 Hz buffer rate).
    private static let spectrumRelease: Float = 0.6

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

    /// Suspend the live session, keeping the dictated text in place. The last
    /// partial is treated as final; a subsequent `start()` resumes by appending
    /// from the cursor. Leaves the mic in `.paused` (orange ring).
    func pause() {
        guard case .listening = state else { return }
        tearDownStream()
        audioLevel = 0
        resetSpectrum()
        state = .paused
    }

    /// Drop a stale `.paused` back to the default idle look — called when the
    /// host control is shown afresh (e.g. a session row reopened) so the orange
    /// pause ring doesn't outlive the viewing it happened in. The dictated text
    /// lives in the caller's binding, so this only clears transient buffers.
    /// Guarded to `.paused` so it can never interrupt a live session.
    func resetPaused() {
        guard case .paused = state else { return }
        partial = ""
        finalizedTranscript = ""
        audioLevel = 0
        resetSpectrum()
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
        resetSpectrum()
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

    /// Fast-attack/slow-release blend so bars pop on speech, ease down on pause.
    private func applySpectrum(_ raw: [Float]) {
        guard raw.count == spectrum.count else { spectrum = raw; return }
        var out = spectrum
        for i in 0..<raw.count {
            out[i] = max(raw[i], out[i] * Self.spectrumRelease)
        }
        spectrum = out
    }

    private func resetSpectrum() {
        spectrum = [Float](repeating: 0, count: bandCount)
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
        // A degraded/absent input reports a 0 Hz format. Bail before building
        // the analyzer, whose log-band math would divide by the sample rate.
        guard format.sampleRate > 0 else {
            state = .failed("No audio input is available.")
            return
        }
        // Audio tap runs on a real-time audio thread. RMS computation is cheap
        // (a few thousand multiplies per ~21 ms buffer at 48 kHz / 1024 frames);
        // hopping to MainActor each buffer to update `audioLevel` is ~47 Hz,
        // which SwiftUI animates smoothly via the easing on the consumer side.
        // The analyzer is created here and captured by the tap closure (not
        // stored on this @MainActor object), so it stays confined to the audio
        // thread and is torn down when the tap closure is released.
        let analyzer = SpectrumAnalyzer(bandCount: bandCount, sampleRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, analyzer] buffer, _ in
            request.append(buffer)
            let level = Self.normalizedRMS(of: buffer)
            let bands = buffer.floatChannelData.map { analyzer.process($0[0], count: Int(buffer.frameLength)) }
            Task { @MainActor [weak self] in
                // Drop late buffers that land after stop()/cancel() so they
                // can't re-light the bars after we've reset them to zero.
                guard let self, case .listening = self.state else { return }
                self.audioLevel = level
                if let bands { self.applySpectrum(bands) }
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
