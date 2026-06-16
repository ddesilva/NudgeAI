# Context for AI sessions

Orientation for anyone (esp. a Claude session) picking up this repo. Not exhaustive —
just the things that aren't obvious from the code or the README. See `README.md` for the
user-facing feature tour.

## What NudgeAI is

A **macOS menu-bar app** (no Dock icon, `LSUIElement`) for building a screenshot +
instruction "change list" to paste into an LLM/terminal agent (Claude Code, Codex).

- Core flow: hotkey (**⌘⇧N**) → drag-select screen regions → type (or **dictate**) an
  instruction per region → Review window → **Export & Copy Prompt**. Output is a folder
  under `~/NudgeAISessions/` plus a paste-ready prompt on the clipboard.
- Secondary features: voice dictation on instruction fields (mic + on-device speech),
  a Library window to browse/re-export past sessions, and asking the focused terminal
  app which tab is active (via Apple Events) to suggest a default paste target.
- Bundle id `com.dilshan.nudgeai`; min macOS **14.0**; GitHub repo `ddesilva/NudgeAI`.

## Build & run

Pure **SwiftPM** (`Package.swift`, swift-tools 6.0, language mode v5) — **no Xcode
project**. The `.app` bundle is assembled by hand in the build scripts.

| Command | What it does |
|---|---|
| `make dev` | `./build.sh debug` — build + assemble `NudgeAI.app`, sign with the stable self-signed identity (or ad-hoc fallback). **No hardened runtime.** Run this after every code change. |
| `make release` | Developer-ID sign **+ hardened runtime + entitlements**, notarize, staple → `NudgeAI-<version>.dmg`. Needs `DEVELOPER_ID` (in gitignored `Makefile.local`) and notarytool profile `nudgeai-notary`. |
| `make dry-run` | Same as release but `SKIP_NOTARIZE=1` — fast way to verify signing/entitlements without the notary round-trip. |
| `make publish` | Tag `v<version>` + `gh release create` with the DMG. |
| `make clean` | Remove `.build`, app bundle, DMGs. |

Helper scripts: `setup-signing.sh` (creates the persistent "Nudge AI Self-Signed"
identity so TCC grants survive rebuilds), `fix-permissions.sh` (resets a stale Screen
Recording grant and rebuilds).

## Code signing & entitlements — the big gotcha

The **dev build has no hardened runtime; the release build does.** Under the hardened
runtime, protected resources need an explicit entitlement or TCC denies/kills the app.
So a feature can work perfectly in `make dev` and silently break only in the shipped DMG.

`NudgeAI.entitlements` (passed to `codesign --entitlements` in both scripts) declares:

- `com.apple.security.device.audio-input` — microphone (voice dictation)
- `com.apple.security.automation.apple-events` — the "focused terminal tab" feature

Screen Recording and Speech Recognition are **TCC-only** (no entitlement needed).
The `NS*UsageDescription` strings live in the root `Info.plist`, which is copied into
the bundle by the build scripts. Note: a *missing usage string* → no prompt at all;
a *missing entitlement* → prompt appears, then access is denied. Different symptoms.

After touching entitlements/signing, verify with:
`codesign -d --entitlements - NudgeAI.app` and `spctl -a -t exec -vvv NudgeAI.app`.

## Source layout (`Sources/NudgeAI/`)

- `Capture/` — screen-region capture
- `Overlay/` — the drag-to-select selection overlay
- `Input/` — instruction panel + voice/mic dictation + live equalizer (most files here)
- `Controls/`, `Shared/` — reusable UI; **button styles** live in
  `Shared/AppButtonStyles.swift` (`PrimaryButtonStyle`/`SecondaryButtonStyle`)
- `Review/` — the post-capture Review window
- `Library/` — browse/re-export saved sessions
- `Export/` — session folder + prompt generation
- `Settings/` — hotkey, retention, storage location
- Top level (4 files) — app entry / menu-bar / session coordination

Tests: `Tests/NudgeAITests/` (`SmokeTests`, `SpectrumAnalyzerTests` — the latter covers
the voice equalizer's spectrum analysis).

## Conventions & things to know

- **Always `make dev` after a Swift change** (not bare `swift build`) so `NudgeAI.app/`
  is refreshed; report the build result.
- **Button styles:** use `PrimaryButtonStyle`/`SecondaryButtonStyle` for every CTA
  (Settings UI is the exception).
- **Stale design docs:** `docs/superpowers/plans|specs/` contain older v0.2 plans. The
  "Workspace"/embedded-terminal direction (SwiftTerm/pty) was **rejected** — don't
  reintroduce it or assume those docs reflect current intent. Brainstorm before building.
- Layout/visual bugs in past sessions: decorative `.fill` images can overflow and eat
  sibling clicks — mark them `.decorative()`; instrument the window-level click path when
  a control seems "dead."
