# Button Style System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current mix of native button modifiers across the app with two custom SwiftUI `ButtonStyle`s — `PrimaryButtonStyle` (blue gradient + glow) and `SecondaryButtonStyle` (dark, bordered, hover-aware) — matching the supplied reference design.

**Architecture:** A single new file `Sources/NudgeAI/Shared/AppButtonStyles.swift` defines both styles plus a small `AppButtonLabel` helper that carries optional leading/trailing SF Symbols and lets the secondary style slide its trailing arrow on hover. The styles are registered as static extensions on `ButtonStyle` so callsites read `.buttonStyle(.primaryApp)` / `.buttonStyle(.secondaryApp)`. Each existing CTA in `InstructionPanelView`, `SessionHUDView`, `LibraryView`, `ReviewView`, and `SettingsView` is migrated according to the mapping in the spec.

**Tech Stack:** SwiftUI on macOS. AppKit-backed visual effects already exist. No new dependencies. SwiftPM build via `make dev` (which delegates to `./build.sh debug`).

**Verification model:** SwiftUI `ButtonStyle` rendering is not meaningfully unit-testable — there are no behavioral assertions, only pixels. Each task therefore verifies via (a) `make dev` succeeding and (b) launching the app and visually exercising the migrated surface. The plan calls these visual checks out explicitly and they are required, not optional.

---

## Spec

Source: `docs/superpowers/specs/2026-06-13-button-style-system-design.md`. Read it before starting Task 1.

---

## Task 1: Create `AppButtonStyles.swift` with `PrimaryButtonStyle`, `SecondaryButtonStyle`, and `AppButtonLabel`

**Files:**
- Create: `Sources/NudgeAI/Shared/AppButtonStyles.swift`

This task lands the entire style system in one file. No callsite migrates yet. The goal is: code compiles, the file is the single source of truth for both styles, and a developer reading the file can understand every state without cross-referencing.

- [ ] **Step 1: Create the new file with both styles and the label helper**

Create `Sources/NudgeAI/Shared/AppButtonStyles.swift` with this exact content:

```swift
import SwiftUI

// MARK: - AppButtonLabel
//
// Shared label used by both PrimaryButtonStyle and SecondaryButtonStyle.
// Carries optional leading/trailing SF Symbols and a flag that lets the
// secondary style slide its trailing arrow on hover (the primary style
// ignores that flag — it never slides).
struct AppButtonLabel: View {
    let title: String
    var leadingIcon: String? = nil
    var trailingIcon: String? = nil

    // Driven by the parent ButtonStyle via PreferenceKey. The label itself
    // does not own hover state; the style does, because the style is what
    // SwiftUI invokes with .onHover and is what we want to keep self-contained.
    var trailingOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            if let leadingIcon {
                Image(systemName: leadingIcon)
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(title)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 13, weight: .bold))
                    .offset(x: trailingOffset)
            }
        }
        .font(.system(size: 15, weight: .semibold))
    }
}

// MARK: - PrimaryButtonStyle
//
// The blue-gradient CTA. One per surface. Carries the glow shadow.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(background(pressed: pressed))
            .overlay(topHighlight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: shadowColor(pressed: pressed),
                radius: shadowRadius(pressed: pressed),
                y: shadowY(pressed: pressed)
            )
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .onHover { hovering in
                isHovered = hovering
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // The gradient brightens on hover and darkens on press.
    private func background(pressed: Bool) -> some View {
        let topBase    = Color(red: 0.20, green: 0.45, blue: 1.00)
        let bottomBase = Color(red: 0.12, green: 0.32, blue: 0.85)

        let top:    Color
        let bottom: Color
        if pressed {
            top    = topBase.opacity(0.92)
            bottom = bottomBase.opacity(0.92)
        } else if isHovered {
            top    = lighten(topBase, by: 0.08)
            bottom = lighten(bottomBase, by: 0.08)
        } else {
            top    = topBase
            bottom = bottomBase
        }

        return LinearGradient(
            colors: [top, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // 1px top-edge sheen — the "lit from above" highlight.
    private var topHighlight: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 1)
            .blendMode(.plusLighter)
            .mask(
                LinearGradient(
                    colors: [Color.white, Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }

    private func shadowColor(pressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if pressed   { return Color.blue.opacity(0.35) }
        if isHovered { return Color.blue.opacity(0.55) }
        return Color.blue.opacity(0.45)
    }

    private func shadowRadius(pressed: Bool) -> CGFloat {
        guard isEnabled else { return 0 }
        if pressed   { return 10 }
        if isHovered { return 14 }
        return 12
    }

    private func shadowY(pressed: Bool) -> CGFloat {
        guard isEnabled else { return 0 }
        if pressed   { return 3 }
        if isHovered { return 5 }
        return 4
    }

    private func lighten(_ color: Color, by amount: CGFloat) -> Color {
        // Pull RGB out via NSColor, bump components, rewrap.
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .blue
        let r = min(1.0, ns.redComponent   + amount)
        let g = min(1.0, ns.greenComponent + amount)
        let b = min(1.0, ns.blueComponent  + amount)
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - SecondaryButtonStyle
//
// Dark, bordered. No shadow. Slides its trailing arrow (if any) on hover.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let slide: CGFloat = (isHovered && !pressed && !reduceMotion) ? 4 : 0

        // We re-inject the hover-driven offset into AppButtonLabel via the
        // environment so the label can apply it to its trailing icon. Buttons
        // that wrap a plain Text just ignore it.
        configuration.label
            .environment(\.appButtonTrailingOffset, slide)
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundFill(pressed: pressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(pressed: pressed), lineWidth: 1)
            )
            .scaleEffect(pressed && !reduceMotion ? 0.98 : 1.0)
            .opacity(isEnabled ? 1.0 : 0.5)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .onHover { hovering in
                isHovered = hovering
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func backgroundFill(pressed: Bool) -> Color {
        if pressed   { return Color.white.opacity(0.10) }
        if isHovered { return Color.white.opacity(0.07) }
        return Color.white.opacity(0.04)
    }

    private func borderColor(pressed: Bool) -> Color {
        if !isEnabled { return Color.white.opacity(0.06) }
        if pressed    { return Color.white.opacity(0.16) }
        if isHovered  { return Color.white.opacity(0.18) }
        return Color.white.opacity(0.10)
    }
}

// MARK: - Trailing-offset environment key
//
// Used by SecondaryButtonStyle → AppButtonLabel to slide a trailing chevron
// on hover. PrimaryButtonStyle never sets this, so the label sees 0.
fileprivate struct AppButtonTrailingOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    fileprivate var appButtonTrailingOffset: CGFloat {
        get { self[AppButtonTrailingOffsetKey.self] }
        set { self[AppButtonTrailingOffsetKey.self] = newValue }
    }
}

// Re-read the offset inside the label so the trailing icon slides.
// We attach this via a small adapter View that AppButtonLabel uses
// internally; consumers don't need to know about it.
extension AppButtonLabel {
    // Convenience: build the label such that its trailing icon picks up the
    // hover-driven offset from the SecondaryButtonStyle. Use this from
    // callsites — never construct AppButtonLabel directly without it.
    @ViewBuilder
    static func make(_ title: String,
                     leadingIcon: String? = nil,
                     trailingIcon: String? = nil) -> some View {
        _AppButtonLabelHost(title: title,
                            leadingIcon: leadingIcon,
                            trailingIcon: trailingIcon)
    }
}

fileprivate struct _AppButtonLabelHost: View {
    let title: String
    let leadingIcon: String?
    let trailingIcon: String?

    @Environment(\.appButtonTrailingOffset) private var trailingOffset

    var body: some View {
        AppButtonLabel(
            title: title,
            leadingIcon: leadingIcon,
            trailingIcon: trailingIcon,
            trailingOffset: trailingOffset
        )
    }
}

// MARK: - ButtonStyle static convenience

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primaryApp: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondaryApp: SecondaryButtonStyle { SecondaryButtonStyle() }
}
```

- [ ] **Step 2: Build**

Run: `make dev`
Expected: SwiftPM builds cleanly; `NudgeAI.app/` is refreshed. No compile errors.

If errors:
- A common one is the `NSColor` bridge: macOS 14+ supports `NSColor(_: Color)`. If the toolchain rejects it, use `NSColor(SwiftUI.Color(...))` or `Color.blue` fallback for the lighten path.
- The `EnvironmentKey` private-vs-fileprivate visibility: the key is `private struct`, the `EnvironmentValues` extension is `fileprivate` — both must stay file-scoped.

- [ ] **Step 3: Commit**

```bash
git add Sources/NudgeAI/Shared/AppButtonStyles.swift
git commit -m "feat(ui): add PrimaryButtonStyle and SecondaryButtonStyle

Two custom SwiftUI ButtonStyles matching the reference button design.
Primary: blue gradient + glow shadow; Secondary: dark bordered with
hover-slide trailing icon. No callsites migrated yet."
```

---

## Task 2: Migrate `InstructionPanelView`

**Files:**
- Modify: `Sources/NudgeAI/Input/InstructionPanelView.swift:175-251` (the `footer` computed property)

The panel has three primary buttons (Copy to Clipboard, Done, Send to…) and one secondary (Next). The header's × close button stays `.plain`.

- [ ] **Step 1: Replace the `footer` computed property**

In `Sources/NudgeAI/Input/InstructionPanelView.swift`, find the `private var footer: some View {` block (around line 175) and replace it in full with:

```swift
    private var footer: some View {
        // First capture → Copy to Clipboard (quick single-shot exit, no review).
        // Multi-capture (index ≥ 2) → Done, which finalises and opens the
        // Sessions library so the user can see the full list. Send to… is
        // also hidden once we're multi-capture; the library is the proper
        // dispatch surface for a full session.
        let isMultiCapture = index >= 2

        return HStack(spacing: 10) {
            Spacer(minLength: 8)

            if isMultiCapture {
                Button(action: commitAndDone) {
                    AppButtonLabel.make("Done")
                }
                .buttonStyle(.primaryApp)
                .help("Save this instruction, end the session, and open Sessions (⌘⏎)")
            } else {
                Button(action: commitAndFinish) {
                    AppButtonLabel.make("Copy to Clipboard",
                                        leadingIcon: "doc.on.clipboard")
                }
                .buttonStyle(.primaryApp)
                .help("Save this instruction, copy the prompt to clipboard, end the session (⌘⏎)")

                if developerModeEnabled {
                    Button(action: commitAndSendTo) {
                        AppButtonLabel.make("Send to…",
                                            leadingIcon: "paperplane")
                    }
                    .buttonStyle(.primaryApp)
                    .help("Save the instruction, then pick an active agent session to deliver the prompt to.")
                }
            }

            Button(action: commit) {
                AppButtonLabel.make("Next", trailingIcon: "arrow.right")
            }
            .buttonStyle(.secondaryApp)
            .help("Save this instruction and capture another region (⏎)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }
```

The header's × close button (lines 54–63) is unchanged.

- [ ] **Step 2: Build**

Run: `make dev`
Expected: Clean build, `NudgeAI.app/` updated.

- [ ] **Step 3: Visually verify the panel**

Launch `NudgeAI.app`, trigger the global hotkey to start a Nudge session, and make a selection so the InstructionPanel appears.

Check:
- Copy to Clipboard renders as the blue gradient with the clipboard icon. Hovering brightens it and grows the glow; clicking briefly darkens and scales it down 2%.
- Next renders as the dark bordered button with a trailing arrow. Hovering slides the arrow ~4px to the right; clicking returns it to 0 and darkens the background.
- The × close in the header is unchanged (still a small grey circle).
- Make a second capture (Next, then re-select) and confirm the panel for index ≥ 2 shows Done (primary) instead of Copy to Clipboard.

If anything looks off, fix in this file and re-run `make dev`.

- [ ] **Step 4: Commit**

```bash
git add Sources/NudgeAI/Input/InstructionPanelView.swift
git commit -m "ui(InstructionPanel): adopt PrimaryButtonStyle / SecondaryButtonStyle

Copy to Clipboard / Done / Send to… → primary blue gradient.
Next → secondary dark bordered with hover-slide arrow."
```

---

## Task 3: Migrate `SessionHUDView`

**Files:**
- Modify: `Sources/NudgeAI/Controls/SessionHUDView.swift:10-58` (the `body`)

The HUD has a primary Done, a secondary Box (add) button, and a cancel ×.

- [ ] **Step 1: Replace the Button blocks in `body`**

In `Sources/NudgeAI/Controls/SessionHUDView.swift`, find the body and replace lines 28–50 (the three Button definitions plus their modifiers) with:

```swift
            Button(action: onAddBox) {
                AppButtonLabel.make("Box", leadingIcon: "plus.viewfinder")
            }
            .buttonStyle(.secondaryApp)

            Button(action: onDone) {
                AppButtonLabel.make("Done")
            }
            .buttonStyle(.primaryApp)
            .disabled(model.count == 0)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
```

Notes:
- The old code dimmed the glow based on `model.count == 0`. We replicate that intent by *disabling* the button when no boxes have been captured — the style's disabled state already reduces opacity and removes the glow.
- The old `.shadow(...)` on the Done button is removed; the style provides its own glow.
- The × cancel button is unchanged.

- [ ] **Step 2: Build**

Run: `make dev`
Expected: Clean build.

- [ ] **Step 3: Visually verify the HUD**

Launch the app, start a session, observe the HUD bar.

Check:
- Box renders as a dark bordered button with the `plus.viewfinder` icon. Hover lightens it.
- Done is the blue gradient with glow. Before any box is captured, it's disabled (50% opacity, no glow). Capture a box → it lights up.
- The × cancel is unchanged.

- [ ] **Step 4: Commit**

```bash
git add Sources/NudgeAI/Controls/SessionHUDView.swift
git commit -m "ui(HUD): adopt PrimaryButtonStyle / SecondaryButtonStyle

Done → primary (auto-disabled while box count is 0).
Box (add) → secondary with leading plus.viewfinder."
```

---

## Task 4: Migrate `LibraryView`

**Files:**
- Modify: `Sources/NudgeAI/Library/LibraryView.swift` — the row action block around lines 155–230 (Copy Prompt, Send to…, Reveal, Delete buttons)

`LibraryView` has four CTAs per row. Copy Prompt and Send to… (developer-mode only) are primary; Reveal and Delete are secondary. Delete keeps `role: .destructive` (SwiftUI uses that for the confirmation-alert and accessibility — it is not just visual).

- [ ] **Step 1: Replace each of the four action buttons**

Find the row footer where Copy Prompt, Send to…, Reveal, and Delete are defined. Replace each `Button { ... } label: { ... } .buttonStyle(.borderedProminent or .bordered) .controlSize(.large) .fixedSize() .help(...)` block as follows.

Copy Prompt (currently `.borderedProminent`):

```swift
            Button {
                Exporter.copyPromptToClipboard(session.promptText)
                LibraryWindowController.shared.close()
            } label: {
                AppButtonLabel.make("Copy Prompt",
                                    leadingIcon: "doc.on.clipboard")
            }
            .buttonStyle(.primaryApp)
            .help("Copy this session's prompt to the clipboard")
```

Send to… (currently `.borderedProminent`, only when `developerModeEnabled`):

```swift
            if developerModeEnabled {
                Button {
                    onSendTo(session.promptText)
                } label: {
                    AppButtonLabel.make("Send to…", leadingIcon: "paperplane")
                }
                .buttonStyle(.primaryApp)
                .help("Send this session's prompt to an active agent window.")
            }
```

Reveal (currently `.bordered`):

```swift
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([session.folder])
            } label: {
                AppButtonLabel.make("Reveal", leadingIcon: "folder")
            }
            .buttonStyle(.secondaryApp)
            .help("Reveal this session's folder in Finder")
```

Delete (currently `.bordered`, `role: .destructive`):

```swift
            Button(role: .destructive) {
                SessionStore.delete(session)
                model.reload()
            } label: {
                AppButtonLabel.make("Delete", leadingIcon: "trash")
            }
            .buttonStyle(.secondaryApp)
            .help("Delete this session from disk")
```

Keep the `Button(role: .destructive)` — that role drives accessibility and any
confirmation-alert role tagging. Do not strip it just because the style is
shared with non-destructive buttons.

The Copy Prompt action body (`Exporter.copyPromptToClipboard` + `LibraryWindowController.shared.close()`) and the Send to… action body (`onSendTo(session.promptText)`) are preserved verbatim above — only the label and `.buttonStyle` change.

- [ ] **Step 2: Build**

Run: `make dev`
Expected: Clean build.

- [ ] **Step 3: Visually verify the Library**

Launch the app, open Sessions (from the menu bar, or after finishing a multi-capture session).

Check:
- Each row's Copy Prompt is the blue gradient primary with clipboard icon.
- In developer mode, Send to… is also blue gradient primary with paperplane icon.
- Reveal is dark bordered secondary.
- Delete is dark bordered secondary. The `role: .destructive` still triggers the macOS destructive-action confirmation if your code path uses one — the style change does not alter that behavior.
- Hover effects (background brighten, slight border) work on Reveal and Delete.

- [ ] **Step 4: Commit**

```bash
git add Sources/NudgeAI/Library/LibraryView.swift
git commit -m "ui(Library): adopt PrimaryButtonStyle / SecondaryButtonStyle

Copy Prompt, Send to… → primary. Reveal, Delete → secondary.
Delete retains role: .destructive."
```

---

## Task 5: Migrate `ReviewView`

**Files:**
- Modify: `Sources/NudgeAI/Review/ReviewView.swift` — the `footer` block around lines 110–140 (Close and Copy to Clipboard buttons)

`ReviewView` has Copy to Clipboard as the primary CTA and Close as the secondary. The per-row up/down/trash buttons stay `.borderless` — they are utility icon buttons.

- [ ] **Step 1: Replace Close and Copy to Clipboard in the footer**

Find the `private var footer: some View {` block. Replace the Close button:

```swift
            Button(action: onClose) {
                AppButtonLabel.make("Close")
            }
            .buttonStyle(.secondaryApp)
```

Replace the Copy to Clipboard button (keep the existing action body that sets `statusMessage`):

```swift
            Button {
                onExport()
                statusMessage = "Exported & prompt copied to clipboard."
            } label: {
                AppButtonLabel.make("Copy to Clipboard",
                                    leadingIcon: "doc.on.clipboard")
            }
            .buttonStyle(.primaryApp)
```

The per-row up / down / trash buttons (around lines 95–104) are unchanged — they remain `.borderless`.

- [ ] **Step 2: Build**

Run: `make dev`
Expected: Clean build.

- [ ] **Step 3: Visually verify Review**

Launch the app, finish a multi-capture session so Review opens (or open a saved session from Library and trigger Review).

Check:
- Copy to Clipboard renders as primary blue gradient. After clicking, the status message ("Exported & prompt copied to clipboard.") still appears beside it.
- Close renders as secondary dark bordered.
- The arrow ↑ / ↓ / trash row controls per annotation are unchanged.

- [ ] **Step 4: Commit**

```bash
git add Sources/NudgeAI/Review/ReviewView.swift
git commit -m "ui(Review): adopt PrimaryButtonStyle / SecondaryButtonStyle

Copy to Clipboard → primary. Close → secondary.
Row utility buttons (↑ ↓ trash) untouched."
```

---

## Task 6: Migrate `SettingsView`

**Files:**
- Modify: `Sources/NudgeAI/Settings/SettingsView.swift` — the hotkey-recorder button (lines 89–98), the Storage section buttons (lines 137–140), and the Menu Bar section button (line 169)

Settings has several utility buttons. None of them are primary CTAs. All become secondary. The hotkey recorder is a special case — it shows the current hotkey or "Press keys…" and supports a disabled state — but visually it follows the secondary style.

- [ ] **Step 1: Replace the hotkey recorder button**

Lines ~89–97. Replace the `Button(action: toggleRecording) { ... }` and its sibling `Button("Reset")`:

```swift
                    Button(action: toggleRecording) {
                        AppButtonLabel.make(
                            recording ? "Press keys…" : model.hotkey.displayString
                        )
                    }
                    .buttonStyle(.secondaryApp)
                    .disabled(!model.hotkeyEnabled)
                    .help("Click, then press a key combination with at least one modifier.")

                    Button(action: { model.resetHotkey() }) {
                        AppButtonLabel.make("Reset")
                    }
                    .buttonStyle(.secondaryApp)
                    .disabled(!model.hotkeyEnabled)
```

Note: the monospaced font on the hotkey display is dropped. The reference design does not use a monospaced font, and the displayString is short enough that a proportional font reads fine. If the user wants the monospaced look back after seeing it, that's a follow-up.

- [ ] **Step 2: Replace the Storage section buttons**

Lines ~137–141. Replace the three `Button(...)` calls:

```swift
                HStack {
                    Button(action: { chooseFolder() }) {
                        AppButtonLabel.make("Change…")
                    }
                    .buttonStyle(.secondaryApp)

                    Button(action: { revealFolder() }) {
                        AppButtonLabel.make("Reveal in Finder")
                    }
                    .buttonStyle(.secondaryApp)

                    Spacer()

                    Button(action: { model.resetSessionsFolder() }) {
                        AppButtonLabel.make("Reset")
                    }
                    .buttonStyle(.secondaryApp)
                    .disabled(model.sessionsFolderIsDefault)
                }
```

- [ ] **Step 3: Replace the Menu Bar section button**

Line ~169. Replace the `Button("Re-pin Now") { ... }`:

```swift
                HStack {
                    Spacer()
                    Button(action: { model.requestMenuBarRepin() }) {
                        AppButtonLabel.make("Re-pin Now")
                    }
                    .buttonStyle(.secondaryApp)
                }
```

- [ ] **Step 4: Build**

Run: `make dev`
Expected: Clean build.

- [ ] **Step 5: Visually verify Settings**

Launch the app, open Settings (from the menu bar).

Check:
- Hotkey recorder button shows the dark bordered style. Click it → label changes to "Press keys…". Disable the global hotkey toggle → button dims to disabled.
- Change… / Reveal in Finder / Reset cluster: all dark bordered. Reset stays disabled when the sessions folder is at its default.
- Re-pin Now: dark bordered.

- [ ] **Step 6: Commit**

```bash
git add Sources/NudgeAI/Settings/SettingsView.swift
git commit -m "ui(Settings): adopt SecondaryButtonStyle for utility buttons

Hotkey recorder, Reset (hotkey), Change…, Reveal in Finder,
Reset (sessions folder), Re-pin Now all become secondary buttons.
Disabled states preserved via .disabled(...)."
```

---

## Task 7: Update the stored feedback memory

**Files:**
- Modify: `/Users/dilshandesilva/.claude/projects/-Users-dilshandesilva-Projects-NudgeAI/memory/feedback_button_style.md`

The old memory says "Reuse the InstructionPanelView button pattern app-wide; don't invent custom gradient/glass/glow ButtonStyles." That direction has now been deliberately overridden. We rewrite the memory so future sessions reflect the new canonical pattern.

- [ ] **Step 1: Rewrite the memory file**

Replace the file contents with:

```markdown
---
name: button-style
description: Use the custom PrimaryButtonStyle / SecondaryButtonStyle in Sources/NudgeAI/Shared/AppButtonStyles.swift for app-wide buttons; don't fall back to .borderedProminent / .bordered for CTAs.
metadata:
  type: feedback
---

For every CTA-class button in the app, use one of the two custom styles
defined in `Sources/NudgeAI/Shared/AppButtonStyles.swift`:

- `.buttonStyle(.primaryApp)` — the dominant action on a surface
  (Copy to Clipboard, Done, Send to…). Blue gradient + glow.
- `.buttonStyle(.secondaryApp)` — supporting actions
  (Next, Close, Reveal, Reset, Change…). Dark, bordered, no glow.

Build labels with `AppButtonLabel.make(title, leadingIcon:, trailingIcon:)`
so the secondary style's hover-slide arrow works correctly.

Small utility icon buttons (close ×, mic, trash, up/down arrows) keep
their existing `.plain` / `.borderless` style — the custom styles are for
labeled CTAs, not toolbar glyphs.

**Why:** This intentionally replaces an earlier rule that said "stick to
native styles." The user decided on 2026-06-13 that the app should have a
distinctive, polished CTA aesthetic instead. See
`docs/superpowers/specs/2026-06-13-button-style-system-design.md`.

**How to apply:** When adding a new button anywhere in the app, decide
whether it is the primary action on its surface or a supporting one, and
pick `.primaryApp` or `.secondaryApp` accordingly. Do not reintroduce
`.borderedProminent` for CTAs. If a destructive primary (red gradient)
is needed in the future, add a third style — don't shoehorn it into the
secondary style.
```

- [ ] **Step 2: Verify the index entry still matches**

Open `/Users/dilshandesilva/.claude/projects/-Users-dilshandesilva-Projects-NudgeAI/memory/MEMORY.md`. The entry is currently:

```
- [Stick to native button styles](feedback_button_style.md) — Reuse the InstructionPanelView button pattern app-wide; don't invent custom gradient/glass/glow ButtonStyles.
```

Replace that line with:

```
- [App-wide button styles](feedback_button_style.md) — Use PrimaryButtonStyle / SecondaryButtonStyle from Sources/NudgeAI/Shared/AppButtonStyles.swift for every CTA.
```

- [ ] **Step 3: No commit needed**

The memory directory is outside the project's git repo, so there is no commit step here. The file edits stand on their own.

---

## Task 8: Full-app sweep + final verification

This is a backstop pass — no new code, just a final check that nothing was missed.

- [ ] **Step 1: Grep for stragglers**

```bash
grep -rn "buttonStyle(.borderedProminent)" Sources/
grep -rn "buttonStyle(.bordered)" Sources/
```

Expected output: empty, except possibly inside files we deliberately left alone (small icon buttons in `ReviewView` lines ~95–104 use `.buttonStyle(.borderless)` — that's a different modifier and is intentional).

If any `.borderedProminent` or `.bordered` survives in a CTA context (i.e., a button with a text label that is not a tiny utility icon), it was missed — go back to the relevant task and add it.

- [ ] **Step 2: End-to-end visual sweep**

Launch `NudgeAI.app/` and walk every surface once more, in this order:

1. Menu bar → Settings → check hotkey recorder + Reset, Change…, Reveal in Finder, Reset (sessions), Re-pin Now. Enable / disable the hotkey to verify the disabled state of the recorder and its Reset.
2. Trigger a Nudge session via the hotkey → HUD appears → Box (secondary), Done (primary, disabled until first capture), × cancel (utility).
3. Make a selection → InstructionPanel appears → Copy to Clipboard (primary) + Next (secondary, hover-slide arrow). If developer mode is on in Settings, also confirm Send to… (primary).
4. Click Next, capture a second box → InstructionPanel now shows Done (primary) instead of Copy to Clipboard.
5. Finish the session → Review opens → Copy to Clipboard (primary), Close (secondary), per-row ↑ ↓ trash unchanged.
6. Open Library from the menu bar → each row: Send to… (primary), Reveal (secondary), Delete (secondary, destructive role preserved).

Confirm at each surface: hover lightens the button, click darkens and shrinks 2%, disabled state visually dims.

- [ ] **Step 3: Commit any residual fixes**

If the sweep surfaced anything (missed callsite, off-color contrast, wrong icon), fix and commit per-surface. If nothing surfaced, no commit needed.

---

## Notes for executors

- **Do not introduce a destructive (red) primary style** in this round. The spec explicitly says it's out of scope. If you find a callsite where you think it's needed, raise it as a follow-up — don't sneak it in.
- **Do not touch keyboard shortcuts.** The custom styles are visual only. `.keyboardShortcut(...)`, the `onKeyPress` handler in `InstructionPanelView`, and ⌘⏎ behavior all remain as-is.
- **Hover detection runs per instance.** Multiple custom-styled buttons in the same row each track their own hover state — no shared state to worry about.
- **`make dev` after every edit** is mandatory per project convention. Do not skip it between tasks.
- **The visual checks are not optional.** SwiftUI ButtonStyles have no unit-test surface; if you don't actually look at the rendered button, you cannot claim the task is done.
