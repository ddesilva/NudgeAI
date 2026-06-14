# Voice Equalizer for Instruction Inputs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While recording an instruction, replace the text editor's left area with a live blue FFT equalizer and give the mic button a glowing blue ring, matching the pasted reference image.

**Architecture:** A pure-DSP `SpectrumAnalyzer` (Accelerate/vDSP) turns the existing mic tap's float buffer into log-spaced, normalized frequency bands. `SpeechDictation` publishes those bands (smoothed) as `@Published spectrum`. `InstructionPanelView` owns the `SpeechDictation` and shows a `Canvas`-based `VoiceEqualizerView` while listening, otherwise the text editor. The mic view is split so the panel can inject the shared `SpeechDictation` without changing the Library/Review call sites.

**Tech Stack:** Swift 6 toolchain (v5 language mode), SwiftUI, AVFoundation (`AVAudioEngine`), Accelerate (`vDSP`), XCTest. Build the app with `make dev`; run unit tests with `swift test`.

---

## File Structure

- **Create** `Sources/NudgeAI/Input/SpectrumAnalyzer.swift` — pure FFT→bands DSP. No AVFoundation; takes raw `Float` samples. Unit-tested.
- **Create** `Tests/NudgeAITests/SpectrumAnalyzerTests.swift` — DSP unit tests.
- **Create** `Sources/NudgeAI/Shared/RecordingStyle.swift` — the shared reference-blue `Color`.
- **Create** `Sources/NudgeAI/Input/VoiceEqualizerView.swift` — `Canvas` bar renderer (pure presentation).
- **Modify** `Sources/NudgeAI/Input/SpeechDictation.swift` — add `@Published spectrum`, run the analyzer in the tap, smooth + reset.
- **Modify** `Sources/NudgeAI/Input/MicButton.swift` — split into `MicButtonCore` (injected dictation) + `MicButton` wrapper (owns dictation); restyle listening state to the blue ring.
- **Modify** `Sources/NudgeAI/Input/InstructionPanelView.swift` — own the `SpeechDictation`, swap equalizer/editor, darken the box while recording.

Library (`LibraryView.swift:310`) and Review (`ReviewView.swift:96`) keep calling `MicButton(text:…)` unchanged.

---

### Task 1: `SpectrumAnalyzer` (TDD)

**Files:**
- Create: `Sources/NudgeAI/Input/SpectrumAnalyzer.swift`
- Test: `Tests/NudgeAITests/SpectrumAnalyzerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/NudgeAITests/SpectrumAnalyzerTests.swift`:

```swift
import XCTest
@testable import NudgeAI

final class SpectrumAnalyzerTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let fftSize = 1024
    private let bandCount = 64

    private func makeAnalyzer() -> SpectrumAnalyzer {
        SpectrumAnalyzer(fftSize: fftSize, bandCount: bandCount, sampleRate: sampleRate)
    }

    private func sine(_ freq: Double, amplitude: Float = 1.0) -> [Float] {
        (0..<fftSize).map { i in
            amplitude * Float(sin(2.0 * .pi * freq * Double(i) / sampleRate))
        }
    }

    private func run(_ samples: [Float], _ analyzer: SpectrumAnalyzer) -> [Float] {
        samples.withUnsafeBufferPointer { analyzer.process($0.baseAddress!, count: samples.count) }
    }

    func testOutputCountMatchesBandCount() {
        XCTAssertEqual(run(sine(1000), makeAnalyzer()).count, bandCount)
    }

    func testSilenceReturnsZeros() {
        let bands = run([Float](repeating: 0, count: fftSize), makeAnalyzer())
        XCTAssertEqual(bands.max() ?? 0, 0, accuracy: 1e-6)
    }

    func testSineIsPeaked() {
        let bands = run(sine(1000), makeAnalyzer())
        let peak = bands.max() ?? 0
        let mean = bands.reduce(0, +) / Float(bands.count)
        XCTAssertGreaterThan(peak, 0)
        XCTAssertGreaterThan(peak, 4 * mean, "energy should concentrate in a few bands")
    }

    func testHigherFrequencyPeaksInHigherBand() {
        let analyzer = makeAnalyzer()
        let low = run(sine(300), analyzer)
        let high = run(sine(5000), analyzer)
        let lowPeak = low.firstIndex(of: low.max() ?? 0) ?? 0
        let highPeak = high.firstIndex(of: high.max() ?? 0) ?? 0
        XCTAssertLessThan(lowPeak, highPeak)
    }

    func testOutputsClampedToUnitRange() {
        let bands = run(sine(1000, amplitude: 50), makeAnalyzer())
        XCTAssertTrue(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testLouderIsNotQuieter() {
        let quiet = run(sine(1000, amplitude: 0.2), makeAnalyzer())
        let loud  = run(sine(1000, amplitude: 0.5), makeAnalyzer())
        XCTAssertGreaterThanOrEqual(loud.max() ?? 0, quiet.max() ?? 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SpectrumAnalyzerTests`
Expected: BUILD FAILURE — `cannot find 'SpectrumAnalyzer' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/NudgeAI/Input/SpectrumAnalyzer.swift`:

```swift
import Accelerate

/// Turns a window of raw mono `Float` samples into log-spaced, normalized
/// (0…1) frequency-band magnitudes for the recording equalizer. Pure DSP with
/// no temporal state, so it is deterministic and unit-testable. Created fresh
/// per listening session and only ever called from one thread (the audio tap).
final class SpectrumAnalyzer {
    private let fftSize: Int
    private let halfSize: Int
    private let bandCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    /// Visual gain applied after converting power → amplitude. Tuned during
    /// visual verification; tests are written to be independent of its value.
    private let gain: Float = 0.02

    private var window: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]   // squared magnitudes per bin
    /// `bandCount + 1` ascending bin indices delimiting each band.
    private let bandEdges: [Int]

    init(fftSize: Int = 1024, bandCount: Int = 64, sampleRate: Double) {
        self.fftSize = fftSize
        self.halfSize = fftSize / 2
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var win = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = win
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realp = [Float](repeating: 0, count: halfSize)
        self.imagp = [Float](repeating: 0, count: halfSize)
        self.magnitudes = [Float](repeating: 0, count: halfSize)
        self.bandEdges = Self.logBandEdges(bandCount: bandCount,
                                           binCount: halfSize,
                                           fftSize: fftSize,
                                           sampleRate: sampleRate)
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Log-spaced bin boundaries from ~80 Hz to min(Nyquist, 12 kHz).
    private static func logBandEdges(bandCount: Int, binCount: Int,
                                     fftSize: Int, sampleRate: Double) -> [Int] {
        let minFreq = 80.0
        let maxFreq = min(sampleRate / 2.0, 12_000.0)
        func bin(_ f: Double) -> Int {
            max(1, min(binCount - 1, Int((f * Double(fftSize) / sampleRate).rounded())))
        }
        return (0...bandCount).map { i in
            let frac = Double(i) / Double(bandCount)
            return bin(minFreq * pow(maxFreq / minFreq, frac))
        }
    }

    /// Window → real FFT → squared magnitudes → log-band average → normalize.
    func process(_ samples: UnsafePointer<Float>, count: Int) -> [Float] {
        let n = min(count, fftSize)
        windowed.withUnsafeMutableBufferPointer { wb in
            for i in 0..<n { wb[i] = samples[i] * window[i] }
            if n < fftSize { for i in n..<fftSize { wb[i] = 0 } }
        }

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wb in
                    wb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cplx in
                        vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let lo = bandEdges[b]
            let hi = max(lo + 1, bandEdges[b + 1])
            var sum: Float = 0
            for bin in lo..<hi { sum += magnitudes[bin] }
            let avgPower = sum / Float(hi - lo)
            let amp = sqrtf(avgPower)
            bands[b] = min(1.0, amp * gain)
        }
        return bands
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SpectrumAnalyzerTests`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/NudgeAI/Input/SpectrumAnalyzer.swift Tests/NudgeAITests/SpectrumAnalyzerTests.swift
git commit -m "feat(input): FFT spectrum analyzer for recording equalizer"
```

---

### Task 2: Shared recording-blue colour

**Files:**
- Create: `Sources/NudgeAI/Shared/RecordingStyle.swift`

- [ ] **Step 1: Add the colour constant**

Create `Sources/NudgeAI/Shared/RecordingStyle.swift`:

```swift
import SwiftUI

extension Color {
    /// Reference blue for the recording equalizer bars and the mic ring
    /// (≈ #4A8CF5). Hardcoded so it matches the design regardless of the
    /// user's macOS accent. Exact value tuned during visual verification.
    static let nudgeRecording = Color(red: 0.29, green: 0.55, blue: 0.96)
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NudgeAI/Shared/RecordingStyle.swift
git commit -m "feat(shared): reference-blue colour for recording UI"
```

---

### Task 3: `VoiceEqualizerView`

**Files:**
- Create: `Sources/NudgeAI/Input/VoiceEqualizerView.swift`

- [ ] **Step 1: Implement the view**

Create `Sources/NudgeAI/Input/VoiceEqualizerView.swift`:

```swift
import SwiftUI

/// Renders a live FFT spectrum as thin vertical bars mirrored about the
/// horizontal centre line, giving the blue "recording waveform" look from the
/// design. Pure presentation — driven entirely by the `spectrum` it is handed.
/// Uses a single `Canvas` so the ~64 bars cost one redraw, not N view updates.
struct VoiceEqualizerView: View {
    /// 0…1 magnitudes, low frequency → high frequency, left → right.
    let spectrum: [Float]
    var color: Color = .nudgeRecording

    var body: some View {
        Canvas { context, size in
            guard !spectrum.isEmpty else { return }
            let count = spectrum.count
            let slot = size.width / CGFloat(count)
            let barWidth = max(1.5, slot * 0.55)
            let midY = size.height / 2
            let maxBar = (size.height / 2) - 2          // vertical padding
            let floorHeight: CGFloat = 1.5              // faint baseline at silence
            for i in 0..<count {
                let level = CGFloat(min(max(spectrum[i], 0), 1))
                let half = max(floorHeight, level * maxBar)
                let x = slot * CGFloat(i) + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: midY - half, width: barWidth, height: half * 2)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(color))
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/NudgeAI/Input/VoiceEqualizerView.swift
git commit -m "feat(input): Canvas-based voice equalizer view"
```

---

### Task 4: Publish a smoothed spectrum from `SpeechDictation`

**Files:**
- Modify: `Sources/NudgeAI/Input/SpeechDictation.swift`

- [ ] **Step 1: Add the published spectrum + smoothing constants**

In `SpeechDictation`, just below the existing `audioLevel` property (after line 33), add:

```swift
    /// Smoothed 0…1 FFT band magnitudes (low→high frequency) while listening,
    /// zeros otherwise. Drives `VoiceEqualizerView`. Fast-attack/slow-release
    /// so bars rise instantly with speech but fall back gently.
    @Published private(set) var spectrum: [Float] = [Float](repeating: 0, count: 64)

    private let bandCount = 64
    /// Per-frame decay applied to the previous band value (slow release).
    private static let spectrumRelease: Float = 0.82
```

- [ ] **Step 2: Run the analyzer inside the audio tap**

Replace the existing `input.installTap(...)` block (currently lines 135–141) with:

```swift
        // The analyzer is created here and captured by the tap closure (not
        // stored on this @MainActor object), so it stays confined to the audio
        // thread and is torn down when the tap closure is released.
        let analyzer = SpectrumAnalyzer(bandCount: bandCount, sampleRate: format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, analyzer] buffer, _ in
            request.append(buffer)
            let level = Self.normalizedRMS(of: buffer)
            let bands = buffer.floatChannelData.map { analyzer.process($0[0], count: Int(buffer.frameLength)) }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.audioLevel = level
                if let bands { self.applySpectrum(bands) }
            }
        }
```

- [ ] **Step 3: Add the smoothing + reset helpers**

Immediately after `tearDownStream()` (after line 114), add:

```swift
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
```

- [ ] **Step 4: Reset the spectrum on stop/cancel**

In `stop()`, after the `audioLevel = 0` line (line 88), add:

```swift
        resetSpectrum()
```

In `cancel()`, after the `audioLevel = 0` line (line 102), add:

```swift
        resetSpectrum()
```

- [ ] **Step 5: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 6: Commit**

```bash
git add Sources/NudgeAI/Input/SpeechDictation.swift
git commit -m "feat(input): publish smoothed FFT spectrum from dictation"
```

---

### Task 5: Split `MicButton` and restyle the listening state

**Files:**
- Modify: `Sources/NudgeAI/Input/MicButton.swift`

Goal: `MicButtonCore` does all the work and takes an injected `@ObservedObject dictation`; `MicButton` becomes a thin wrapper that owns the `@StateObject`. The public `MicButton(text:characterCap:)` initializer is unchanged, so `LibraryView` and `ReviewView` are untouched.

- [ ] **Step 1: Rename the struct to `MicButtonCore` and inject the dictation**

In `MicButton.swift`, change the declaration (lines 7–14) from:

```swift
struct MicButton: View {
    @Binding var text: String
    var characterCap: Int? = nil

    @StateObject private var dictation = SpeechDictation()
    @State private var insertionStart: Int = 0
    @State private var lastWrittenLength: Int = 0
    @State private var dictationOffAlertShown: Bool = false
```

to:

```swift
/// Core mic control. Takes an injected `SpeechDictation` so a host (the
/// instruction panel) can share the same recording state with the equalizer.
/// Most callers use the `MicButton` wrapper below, which owns the dictation.
struct MicButtonCore: View {
    @ObservedObject var dictation: SpeechDictation
    @Binding var text: String
    var characterCap: Int? = nil

    @State private var insertionStart: Int = 0
    @State private var lastWrittenLength: Int = 0
    @State private var dictationOffAlertShown: Bool = false
```

- [ ] **Step 2: Restyle the listening visuals to the blue ring**

Replace the `ZStack { … }` inside `body` (currently lines 18–38) with:

```swift
            ZStack {
                if isListening {
                    // Outer ring that brightens + grows with the live mic level.
                    Circle()
                        .stroke(Color.nudgeRecording.opacity(0.30 + 0.45 * Double(dictation.audioLevel)),
                                lineWidth: 2)
                        .scaleEffect(1.16 + 0.12 * CGFloat(dictation.audioLevel))
                        .blur(radius: 3)
                        .animation(.easeOut(duration: 0.12), value: dictation.audioLevel)
                    // Dark centre disc so the white glyph + blue ring read like
                    // the reference image.
                    Circle().fill(Color.black.opacity(0.85))
                    Circle()
                        .stroke(Color.nudgeRecording, lineWidth: 3)
                        .shadow(color: Color.nudgeRecording.opacity(0.8), radius: 8)
                } else {
                    Circle().fill(backgroundFill)
                    Circle().stroke(strokeColor, lineWidth: 1)
                }
                Image(systemName: symbolName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(symbolColor)
            }
            .frame(width: 64, height: 64)
            .animation(.easeInOut(duration: 0.2), value: isListening)
```

- [ ] **Step 3: Add the `MicButton` wrapper at the end of the file**

After the closing brace of `MicButtonCore` (the struct that ends at the old line 219, before `IconCircleButtonStyle`/end of file), add:

```swift

/// Self-owning mic button for callers that don't need to observe recording
/// state (Library draft note, Review per-region fields). Owns the dictation
/// and forwards to `MicButtonCore`. Public init is unchanged from the original
/// `MicButton`, so existing call sites need no edits.
struct MicButton: View {
    @Binding var text: String
    var characterCap: Int? = nil

    @StateObject private var dictation = SpeechDictation()

    var body: some View {
        MicButtonCore(dictation: dictation, text: $text, characterCap: characterCap)
    }
}
```

- [ ] **Step 4: Build to verify it compiles (and Library/Review are unaffected)**

Run: `swift build`
Expected: build succeeds with no changes needed in `LibraryView.swift` or `ReviewView.swift`.

- [ ] **Step 5: Commit**

```bash
git add Sources/NudgeAI/Input/MicButton.swift
git commit -m "refactor(input): split MicButtonCore + blue recording ring"
```

---

### Task 6: Wire the equalizer into `InstructionPanelView`

**Files:**
- Modify: `Sources/NudgeAI/Input/InstructionPanelView.swift`

- [ ] **Step 1: Own the shared dictation**

After the existing `@State private var text` / `@FocusState` declarations (lines 15–16), add:

```swift
    @StateObject private var dictation = SpeechDictation()
```

And add a computed helper just below `panelWidth` (after line 24):

```swift
    private var isRecording: Bool {
        dictation.state == .listening || dictation.state == .preparing
    }
```

- [ ] **Step 2: Swap the editor's left area between equalizer and text**

In `editor`, replace the left `ZStack(alignment: .topLeading) { … }` (currently lines 109–155) so the equalizer shows while recording:

```swift
            ZStack(alignment: .topLeading) {
                if isRecording {
                    VoiceEqualizerView(spectrum: dictation.spectrum)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 28)
                        .transition(.opacity)
                } else {
                    if text.isEmpty {
                        // Placeholder must sit at the same insets as the editor's
                        // first glyph, otherwise it jumps when typing begins.
                        Text("Describe the change you want for this highlighted area…")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                            .padding(.top, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 7)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .focused($editorFocused)
                        .onChange(of: text) { _, newValue in
                            if newValue.count > Self.maxCharacters {
                                text = String(newValue.prefix(Self.maxCharacters))
                            }
                        }
                        // Enter commits; Shift+Enter inserts a newline; ⌘+Enter
                        // commits and ends the session; Esc cancels.
                        .onKeyPress { press in
                            switch press.key {
                            case .return:
                                if press.modifiers.contains(.shift) { return .ignored }
                                if press.modifiers.contains(.command) {
                                    if index >= 2 { commitAndDone() } else { commitAndFinish() }
                                } else {
                                    commit()
                                }
                                return .handled
                            case .escape:
                                onCancel()
                                return .handled
                            default:
                                return .ignored
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 3: Inject the shared dictation into the mic, and animate the swap**

Replace the `MicButton(...)` line (currently line 158) with:

```swift
            MicButtonCore(dictation: dictation, text: $text, characterCap: Self.maxCharacters)
                .padding(.trailing, 10)
```

And add an animation modifier on the editor `HStack` so the equalizer fades in/out. Change the `HStack(alignment: .center, spacing: 10) {` opening (line 108) — leave it as-is — and add, right after the `.frame(height: 174)` line (line 161):

```swift
        .animation(.easeInOut(duration: 0.2), value: isRecording)
```

- [ ] **Step 4: Darken the box while recording**

Replace the editor box `.background(...)` (currently lines 162–165) with:

```swift
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isRecording ? Color.black.opacity(0.7) : Color.primary.opacity(0.04))
        )
```

- [ ] **Step 5: Refocus the editor when recording ends**

Add an `.onChange` to the editor view, right after the `.padding(.horizontal, 18)` that closes `editor` (line 174):

```swift
        .onChange(of: dictation.state) { _, newState in
            if newState == .idle { editorFocused = true }
        }
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/NudgeAI/Input/InstructionPanelView.swift
git commit -m "feat(input): show live equalizer while recording an instruction"
```

---

### Task 7: Build the app and verify manually

**Files:** none (verification + tuning only).

- [ ] **Step 1: Run the unit tests**

Run: `swift test --filter SpectrumAnalyzerTests`
Expected: all 6 tests PASS.

- [ ] **Step 2: Build the app bundle**

Run: `make dev`
Expected: build succeeds and `NudgeAI.app/` is refreshed.

- [ ] **Step 3: Manual verification (native — user observes)**

Launch NudgeAI, start a session, capture a region to open the instruction panel, then click the mic:
- The editor area becomes a dark field with **blue bars** that move with your voice; low/high tones move different bars.
- The mic shows a **white glyph in a dark disc inside a glowing blue ring** that pulses with loudness.
- On stop, the bars disappear and the **transcribed text** is in the editor, which regains focus.
- Quiet input shows a faint baseline of bars rather than an empty field.

- [ ] **Step 4: Tune to match the reference (if needed)**

If bars peg at full height for normal speech or look too faint, adjust `SpectrumAnalyzer.gain` (lower = shorter bars). If the blue is off, adjust `Color.nudgeRecording`. If the dark field is too dark/light, adjust the `Color.black.opacity(0.7)` in `InstructionPanelView`. Rebuild with `make dev` and re-observe. Commit any tuning:

```bash
git add -A && git commit -m "chore(input): tune equalizer gain/colour to match reference"
```

---

## Self-Review

**Spec coverage:**
- "only while recording" → Task 6 Step 2 (`if isRecording`). ✓
- "real FFT spectrum" → Task 1 (`SpectrumAnalyzer`, vDSP). ✓
- "blue" → Task 2 colour + Task 3/5 usage. ✓
- "mirrored waveform bars" → Task 3 Canvas. ✓
- "glowing blue mic ring, pulses on level" → Task 5 Step 2. ✓
- "publish smoothed spectrum / reset at rest" → Task 4. ✓
- "darken box while recording" → Task 6 Step 4. ✓
- "Library/Review untouched" → Task 5 wrapper keeps `MicButton(text:characterCap:)`. ✓
- "DSP unit-tested" → Task 1 tests. ✓
- "manual native verification" → Task 7. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. ✓

**Type consistency:** `SpectrumAnalyzer(fftSize:bandCount:sampleRate:)` and `process(_:count:) -> [Float]` identical in Task 1 (impl + tests) and Task 4 (caller). `MicButtonCore(dictation:text:characterCap:)` identical in Task 5 (def) and Task 6 (use). `spectrum`, `isRecording`, `Color.nudgeRecording`, `applySpectrum`, `resetSpectrum` used consistently. ✓

**Note on `Accelerate` linking:** On macOS, `import Accelerate` auto-links the framework for SwiftPM targets; no `Package.swift` change is expected. If a link error appears, add `linkerSettings: [.linkedFramework("Accelerate")]` to the `NudgeAI` executable target.
