# Live FFT equalizer for instruction inputs

**Date:** 2026-06-14
**Status:** Approved (design)

## Goal

Restyle the instruction-input recording UI to match the pasted reference: a
horizontal blue audio equalizer that animates from live microphone levels while
recording, with a circular mic button wrapped in a glowing blue ring. When not
recording, the input stays a normal text editor.

## Decisions (from brainstorming)

- **When it shows:** only while recording. Idle = normal `TextEditor`. While the
  dictation is `listening`/`preparing`, the editor's left area is replaced by the
  equalizer; stopping returns to the text editor with the transcribed words.
- **Animation:** a real **FFT spectrum** (graphic-EQ), not a scrolling time-domain
  buffer and not a single-level reactive field. Low/high bands move independently.
- **Colour:** a hardcoded reference **blue** (≈ `#4A8CF5`), matching the image
  regardless of the user's macOS accent. Used by both the bars and the mic ring.

## Architecture & data flow

```
AVAudioEngine tap (audio thread, ~47 Hz)
  ├─ RMS  → audioLevel   (existing — drives mic ring pulse)
  └─ SpectrumAnalyzer.process(samples) → [Float] bands  (NEW, FFT)
        → hop to MainActor → attack/release smoothing → @Published spectrum
                                                              │
        InstructionPanelView owns @StateObject SpeechDictation
              ├─ left area: VoiceEqualizerView(spectrum)  ← while listening
              │             TextEditor                    ← otherwise
              └─ right: MicButtonCore (blue glowing ring, pulses on audioLevel)
```

## Units

### New

**`SpectrumAnalyzer`** — pure DSP, no AVFoundation dependency.
- `init(fftSize: Int = 1024, bandCount: Int = 64, sampleRate: Double)`.
- Owns a `vDSP.FFT` setup, a precomputed Hann window, and reused scratch buffers,
  all created once in `init` (no allocation in the steady-state hot path beyond the
  small returned array).
- `process(_ samples: UnsafePointer<Float>, count: Int) -> [Float]`:
  window → real FFT → magnitudes (512 bins for a 1024-pt FFT) → average into
  `bandCount` **log-spaced** bands → normalize to 0…1 (gain + clamp, thresholds
  tunable). Deterministic — no temporal state — so it is unit-testable.
- Single-threaded: only ever called from the audio-tap thread.

**`VoiceEqualizerView`** — pure SwiftUI presentation.
- `init(spectrum: [Float], color: Color)`.
- Renders thin vertical bars with a `Canvas` (one redraw, not N `Rectangle`s),
  **mirrored about the horizontal centre line** so the result reads as a waveform.
- Applies a small baseline floor so silence shows faint bars (like the quiet
  sections of the reference image), with rounded bar caps.

### Modified

**`SpeechDictation`**
- Add `@Published private(set) var spectrum: [Float]` (length `bandCount`, zeros at
  rest).
- In the audio tap, run `SpectrumAnalyzer.process` alongside the existing RMS, hop
  to `MainActor`, apply **fast-attack / slow-release** smoothing
  (`smoothed[i] = max(new[i], smoothed[i] * release)`, release ≈ 0.85), publish.
- Reset `spectrum` to zeros on `stop()` / `cancel()`, same as `audioLevel`.
- Create the analyzer in `beginListening` (needs the input `sampleRate`); the tap
  closure captures it.

**`MicButton` → split into wrapper + core** (so Library/Review call sites are
untouched).
- **`MicButtonCore`** — takes `@ObservedObject var dictation` (injected) plus the
  existing `text` binding and `characterCap`. Holds all current rendering, toggle,
  permission, `applyPartial`, insertion-point, and dictation-off-alert logic.
- **`MicButton(text:characterCap:)`** — thin wrapper that owns
  `@StateObject private var dictation` and renders `MicButtonCore`. Public init is
  unchanged, so `LibraryView:310` and `ReviewView:96` need **zero** changes.
- Restyle the **listening/preparing** state to match the image: dark centre disc +
  white `mic.fill` + a bright blue stroked ring with a soft glow (`.shadow`), the
  ring's intensity/scale reacting to `audioLevel`. `denied`/`failed` stay orange.

**`InstructionPanelView`**
- Own `@StateObject private var dictation = SpeechDictation()`; pass it to
  `MicButtonCore` and to `VoiceEqualizerView`.
- In the editor row, show `VoiceEqualizerView(spectrum:color:)` while
  `isListening`, otherwise the existing placeholder + `TextEditor`.
- While recording, darken the editor box to near-black so the blue bars pop
  (matches the image's dark field). The focus-border treatment still applies when
  not recording.
- Transcribed text reappears in the `TextEditor` on stop — already handled by
  `MicButtonCore.applyPartial` writing into the bound `text`.

### Shared

A reference-blue constant (≈ `#4A8CF5`) shared by the bars and the mic ring. Exact
value tuned during visual verification.

## Testing

TDD on the DSP core (`NudgeAITests/SpectrumAnalyzerTests`):
- silence (all-zero samples) → all bands ≈ 0;
- a 1 kHz sine at 48 kHz, fftSize 1024 → the band covering 1 kHz is the maximum,
  bands far from it stay low;
- a louder sine → a higher (monotonically) normalized value, clamped ≤ 1;
- output length == `bandCount`.

The SwiftUI views, the mic-ring styling, and the live audio tap are verified
manually in the running app (native macOS — not screenshot-verifiable here).

## Out of scope

- Library and Review mic-button visuals (unchanged).
- Persisting/serializing waveforms; playback or scrubbing of recorded audio.
- Changing the dictation/transcription behaviour itself.
