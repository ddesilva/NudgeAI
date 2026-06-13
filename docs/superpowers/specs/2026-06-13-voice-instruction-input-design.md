# Voice instruction input — design

**Status:** Approved 2026-06-13
**Branch:** `prototype-next-level`

## Goal

Let the user dictate instructions instead of (or in addition to) typing, in every place the app accepts an instruction. Speech-to-text is on-device, free, and adds no third-party dependencies.

## Inputs in scope

The three existing instruction editors. Same control gets attached to each.

| File | Site | Field shape |
| --- | --- | --- |
| `Sources/NudgeAI/Input/InstructionPanelView.swift:128` | The floating panel that appears over a freshly captured region. | `TextEditor` with a 500-character cap. |
| `Sources/NudgeAI/Library/LibraryView.swift:306` (inside `InstructionField`) | Inline editable instruction for an existing capture row in the library detail pane. Commits on focus loss. | `TextField(axis: .vertical)`. |
| `Sources/NudgeAI/Review/ReviewView.swift:87` | The multi-capture review window's per-annotation editor. | `TextEditor`. |

Nothing else in the app accepts an instruction string today, so this is the full set.

## Backend

Apple's `SFSpeechRecognizer` driven by an `AVAudioEngine` tap on the default input device.

- **On-device when available.** Set `requiresOnDeviceRecognition = true` before each recognition task. On Apple Silicon with the required model installed this keeps audio on the machine; on older Macs that flag is silently ignored and recognition falls back to Apple's server path (still free, still works without an API key).
- **Locale.** `SFSpeechRecognizer()` initialised with `Locale.autoupdatingCurrent`. No in-app language picker.
- **Permissions.** Two new `Info.plist` keys:
  - `NSMicrophoneUsageDescription` — *"Nudge AI listens to your voice when you press the microphone button on an instruction field, so you can dictate instead of type."*
  - `NSSpeechRecognitionUsageDescription` — *"Nudge AI transcribes the audio you dictate into the instruction field. On Apple Silicon this happens on-device; on older Macs the audio is sent to Apple for transcription."*
- **Request flow.** The first time any mic button is pressed:
  1. Request `AVCaptureDevice.requestAccess(for: .audio)`.
  2. If granted, request `SFSpeechRecognizer.requestAuthorization`.
  3. If either is denied, the button shows a tooltip linking to the relevant pane of System Settings (Privacy → Microphone / Privacy → Speech Recognition) and does not start listening.
  4. After a grant, both flags are sticky — subsequent presses skip straight to listening.

## UX

A single small button, dropped in the bottom-right corner of each editor's frame so it overlays the text area without affecting the panel's overall layout.

- **Idle state.** 22pt `mic` SF symbol, foreground `.secondary`. Standard `.borderless` button. Tooltip: *"Dictate (⌘;)"* — see hotkey below.
- **Listening state.** Symbol swaps to `mic.fill`, tint shifts to `.red`, and a subtle 1s opacity pulse plays. The button remains tappable.
- **Tap to start, tap to stop.** First tap requests permission (if needed), starts the audio engine, and begins a recognition task. Second tap stops both, treats the most recent partial result as the final result, and dismisses the listening state.
- **Live transcript.** Partial results are streamed into the field at the cursor position as they arrive. The cursor advances past the inserted text so the user sees it being written in real time.
- **Cancel.** Pressing Esc while the field is focused and listening cancels the recognition task and reverts the field to whatever text it had at the moment listening started. In `InstructionPanelView` this takes priority over the existing Esc-cancels-the-panel handler — Esc first cancels an active dictation; only if no dictation is active does Esc fall through to cancelling the panel.
- **No hotkey for v1.** Mic is mouse-only. ⌘; is taken by macOS for "Find Next Misspelled Word", ⌘\ conflicts with potential future bindings, and Fn-Fn can't be intercepted reliably from an `LSUIElement` process. We can revisit once we see how often the user actually wants a hotkey vs. the click.
- **Insert at cursor.** Dictated text is inserted at the current selection range, matching the macOS Dictation convention. If text is selected, the dictated text replaces the selection; otherwise it inserts at the caret. This applies to both `TextEditor` and `TextField`.
- **Cap.** `InstructionPanelView` enforces a 500-character cap on the bound string. The mic button inherits this cap by writing through the same `Binding<String>`; the existing `onChange` truncation already covers the dictation path, no separate cap logic needed.

## Architecture

Two new files, both under `Sources/NudgeAI/Input/`:

### `SpeechDictation.swift`

`@MainActor final class SpeechDictation: ObservableObject`. One instance per `MicButton`, owned by the button's `@StateObject`. Encapsulates the recognition session lifecycle.

- **State machine.** `@Published var state: State` where `State` is `case idle, preparing, listening, denied(Reason), failed(Error)`. The button reads this to render itself.
- **Streaming output.** `@Published var partial: String` — most recent partial transcript. `MicButton` observes this via `onChange` and forwards each delta into the bound `String`.
- **Public API.** `func start()`, `func stop()`, `func cancel()`. `start()` is idempotent on re-press while listening (no-op + a debug log). `cancel()` aborts without committing.
- **Internals.** Holds an `AVAudioEngine`, an `SFSpeechAudioBufferRecognitionRequest`, and an `SFSpeechRecognitionTask`. On `start()`: install a tap on the engine's input node, push buffers into the request, observe results via the task's callback. On `stop()`: end the request, await the final result, tear down the tap and the engine. On `cancel()`: tear down without awaiting.
- **Errors.** Audio engine start failures, recognition task failures, and the locale being unsupported all surface as `state = .failed(...)`. The button renders a tooltip with the underlying message; no modal alert (matches the app's existing low-friction tone).

### `MicButton.swift`

A small SwiftUI view used in three places.

```swift
struct MicButton: View {
    @Binding var text: String

    var body: some View { ... }
}
```

- Wraps a `SpeechDictation` (`@StateObject`) and a `FocusedSelection` (`@StateObject`).
- Reads the active caret/selection from `FocusedSelection` (see below) at the moment dictation starts; ignores subsequent caret moves while listening.
- On each `SpeechDictation.partial` delta, replaces the substring of `text` covering `[insertStart, insertStart + lastWrittenLength)` with the new partial and updates `lastWrittenLength`. Result: the field shows the live transcript growing in place, without duplicate accumulation.
- If no caret position is available when dictation starts, falls back to appending at the end of `text`.

### `FocusedSelection.swift`

Both `TextField` and `TextEditor` in SwiftUI hide the native `NSTextView` and don't expose the caret position to SwiftUI. Two options for getting it:

- **A. `NSTextView` introspection.** Find the first-responder `NSTextView` and read `selectedRange`. Most precise; matches macOS Dictation behaviour exactly.
- **B. End-of-string append.** Ignore the caret and always append dictated text to the end of `text`. Simpler, but feels noticeably worse if the user has positioned the caret mid-string before tapping mic.

**We ship A.** A small helper, `Sources/NudgeAI/Input/FocusedSelection.swift`, reads `NSApp.keyWindow?.firstResponder` on demand; if it's an `NSTextView`, returns its `selectedRange`. `MicButton` calls `FocusedSelection.current()` once at the moment dictation starts and uses that as the insertion point for the whole session. If no `NSTextView` is first responder when the user taps mic (shouldn't happen — the button is inside a field), the button falls back to behaviour B for that one press and logs a warning.

This is a synchronous, on-demand lookup — no observation, no environment plumbing. Keeps the API surface small.

## Data flow

```
[ user taps mic ]
        │
        ▼
MicButton.toggle()
        │
        ├─ first ever press? → request mic + speech auth, gate on result
        │
        ▼
SpeechDictation.start()
        │
        ├─ installs AVAudioEngine input tap
        ├─ creates SFSpeechAudioBufferRecognitionRequest (.shouldReportPartialResults = true,
        │                                                  .requiresOnDeviceRecognition = true)
        └─ creates SFSpeechRecognitionTask, observes its (SFSpeechRecognitionResult?, Error?) callback
                 │
                 ▼ for each partial result
        partial = result.bestTranscription.formattedString
                 │
                 ▼
MicButton observes `partial`, writes the new transcript into `text` at `selection`,
overwriting any previous partial (so the field shows the live, growing transcript instead
of accumulating duplicates).
                 │
                 ▼
[ user taps mic again ] → SpeechDictation.stop() → final result is the last partial we already wrote
```

## Error handling

| Condition | Resulting state | What the user sees |
| --- | --- | --- |
| Mic denied | `.denied(.microphone)` | Mic icon stays gray, tooltip explains + opens Privacy → Microphone on click. |
| Speech recognition denied | `.denied(.speech)` | Same pattern, tooltip routes to Privacy → Speech Recognition. |
| `SFSpeechRecognizer(locale:)` returns nil for the system locale | `.failed(.unsupportedLocale)` | Tooltip: *"Voice input isn't available for <system-locale>."* Button stays gray. |
| Audio engine fails to start | `.failed(error)` | Tooltip with the localised error string. Mic resets to idle on next press. |
| Recognition task fails mid-stream | `.failed(error)` + listening session ends | Whatever partial text was already written stays; tooltip shows the error. |

No modal alerts — they would interrupt the capture flow. The button itself is the entire surface for error reporting.

## Testing

Speech recognition is gnarly to unit-test because it requires audio input and a model. Approach:

- **Pure logic** — `SpeechDictation.State` transitions and the partial-result write-through into a bound string are testable without touching `SFSpeechRecognizer`. Inject a recognizer protocol (`SpeechRecognizing`) so tests can feed fake partial results and assert the field's bound string reflects each delta and respects the `selection`-based insertion point.
- **Permission gating** — unit-test the gate using a fake `Authorizer` protocol that returns scripted outcomes.
- **Manual smoke** — three checklist items added to `Makefile.local.example`:
  1. InstructionPanel mic during capture: speak → text streams into the field → commit + paste works.
  2. Library row mic: speak into an existing capture's instruction → commit on focus loss persists.
  3. Review mic: speak into one of multiple captures → only that one updates.

No XCTest harness exists in CI (no Xcode in the build env per session memory), so tests are written and run on a dev machine.

## Out of scope

- Language picker (uses system locale).
- Re-recording over previously-committed instructions (mic only affects the current draft `Binding<String>`).
- Showing audio level / waveform.
- Global hotkey — only field-scoped ⌘;.
- Punctuation hints / custom vocab lists.

## File summary

### Created

| Path | Responsibility |
| --- | --- |
| `Sources/NudgeAI/Input/SpeechDictation.swift` | State-machine + lifecycle for one dictation session. |
| `Sources/NudgeAI/Input/MicButton.swift` | SwiftUI button that drives a `SpeechDictation` and writes into a bound string. |
| `Sources/NudgeAI/Input/FocusedSelection.swift` | NSTextView introspection helper to publish the current caret/selection. |
| `Tests/NudgeAITests/SpeechDictationTests.swift` | State transitions + partial-write logic via injected fakes. |

### Modified

| Path | Change |
| --- | --- |
| `Info.plist` | Add `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`. |
| `Sources/NudgeAI/Input/InstructionPanelView.swift` | Drop `MicButton` into the editor's overlay corner. |
| `Sources/NudgeAI/Library/LibraryView.swift` | Drop `MicButton` into `InstructionField`'s corner. |
| `Sources/NudgeAI/Review/ReviewView.swift` | Drop `MicButton` into each row's editor corner. |
| `Makefile.local.example` | Append manual smoke checklist for the three sites. |
