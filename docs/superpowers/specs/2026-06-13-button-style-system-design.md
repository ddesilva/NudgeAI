# Button Style System — Design

**Date:** 2026-06-13
**Status:** Approved

## Goal

Replace the current mix of `.borderedProminent` / `.bordered` / `.borderless` /
`.plain` button modifiers across the app with a deliberate two-role custom
button style system that matches the reference image (blue-gradient primary CTA
+ dark-bordered secondary action with hover/pressed/disabled states).

This intentionally overrides earlier guidance that said to "stick to native
button styles." The new direction is: native is no longer the target —
distinctive, polished CTAs are.

Tiny utility icon buttons (close X, mic, trash, up/down arrows) are out of
scope; they stay on `.plain` / `.borderless`.

## The two styles

Both live in a new file: `Sources/NudgeAI/Shared/AppButtonStyles.swift`.

### `PrimaryButtonStyle`

The blue gradient CTA. One per surface — used for the dominant action.

- **Background:** vertical `LinearGradient`
  - top:    `Color(red: 0.20, green: 0.45, blue: 1.00)` (≈ #3373FF)
  - bottom: `Color(red: 0.12, green: 0.32, blue: 0.85)` (≈ #1F52D9)
- **Shape:** `RoundedRectangle(cornerRadius: 10, style: .continuous)`
- **Foreground:** `Color.white`
- **Font:** `.system(size: 15, weight: .semibold)`
- **Padding:** horizontal 18, vertical 11 (tunable per callsite via the
  existing `padding()` modifiers each label already has — the style does not
  fight those; it adds *minimum* padding only when label has no padding of
  its own)
- **Inner top highlight:** 1px top-edge stroke `Color.white.opacity(0.18)`
  inside the shape (the lit-from-above sheen)
- **Drop shadow / glow:**
  - default:  `Color.blue.opacity(0.45)`, radius 12, y 4
- **States:**
  - **hover**   — gradient lifted ~+8% lightness; shadow opacity 0.55,
    radius 14, y 5
  - **pressed** — gradient ~−6% darker; shadow opacity 0.35; `scaleEffect(0.98)`
  - **disabled** (`@Environment(\.isEnabled) == false`) — entire button at
    opacity 0.5; no shadow
- **Animation:** `.easeOut(duration: 0.12)` on hover/press transitions.
- **Hover detection:** `.onHover { isHovered = $0 }` inside the style's
  `makeBody`.

### `SecondaryButtonStyle`

The dark bordered button. Used for secondary actions and utility CTAs.

- **Background:** `Color.white.opacity(0.04)` on top of the host material
- **Border:** `Color.white.opacity(0.10)` 1px stroke, corner radius 10
- **Foreground:** `Color.white.opacity(0.92)`
- **Font:** `.system(size: 15, weight: .semibold)`
- **Padding:** horizontal 18, vertical 11 (same rule as primary)
- **States:**
  - **hover**   — background 0.07, border 0.18; if a trailing chevron/arrow
    SF Symbol is present (see optional initializer below), it slides +4px
    right via `.offset(x:)` animated `.easeOut(0.15)`
  - **pressed** — background 0.10; `scaleEffect(0.98)`; arrow returns to x=0
  - **disabled** — opacity 0.5; border 0.06
- **No drop shadow.**

### Optional icon-aware initializer

To keep callsites short, expose a small `View` helper:

```swift
struct AppButtonLabel: View {
    let title: String
    var leadingIcon: String? = nil
    var trailingIcon: String? = nil
    var trailingIconSlides: Bool = false  // bound to hover from parent
    // body: HStack with optional leading SF Symbol + Text + optional trailing
    // SF Symbol, with the trailing-slide effect plumbed via PreferenceKey or
    // a small @State coordinated with the style.
}
```

Implementation detail to decide during the plan stage: the cleanest way to
share hover state between style and label is for the style itself to lay out
the icon (via a custom protocol-conformance), OR for both halves to read a
shared `@State`. We will pick during writing-plans — for now, the public
surface is:

```swift
Button(action: ...) { AppButtonLabel(title: "Next", trailingIcon: "arrow.right") }
    .buttonStyle(.secondaryApp)

Button(action: ...) { AppButtonLabel(title: "Copy to Clipboard",
                                     leadingIcon: "doc.on.clipboard") }
    .buttonStyle(.primaryApp)
```

We add `extension ButtonStyle where Self == PrimaryButtonStyle { static var
primaryApp: Self { Self() } }` and the equivalent for secondary, so callsites
read naturally.

## Per-callsite mapping

The following table is the source of truth for the apply phase. Tiny utility
icon buttons not listed here keep their current style.

| File | Button | New style |
|---|---|---|
| `Input/InstructionPanelView.swift` | Copy to Clipboard | primary (leading `doc.on.clipboard`) |
| | Done (multi-capture, index ≥ 2) | primary |
| | Send to… (developer mode) | primary (leading `paperplane`) |
| | Next | secondary (trailing `arrow.right`) |
| | × close (header) | unchanged — `.plain` |
| `Controls/SessionHUDView.swift` | Done | primary |
| | Box (add) | secondary (leading `plus.viewfinder`) |
| | × cancel | unchanged — `.borderless` |
| `Library/LibraryView.swift` | Copy Prompt | primary (leading `doc.on.clipboard`) |
| | Send to… (developer mode) | primary (leading `paperplane`) |
| | Reveal | secondary |
| | Delete | secondary, `role: .destructive` preserved |
| `Review/ReviewView.swift` | Copy to Clipboard | primary |
| | Send to… (developer mode) | primary (leading `paperplane`) |
| | Close | secondary |
| | ↑ / ↓ / trash row | unchanged — `.borderless` |
| `Settings/SettingsView.swift` | (unchanged — see note below) | n/a — keep native Form styling |

Destructive primary (red gradient) is intentionally not in this scope. If a
destructive emphasis becomes needed later, it gets added as a third role.

**Settings panel — explicitly skipped.** SettingsView renders inside a native
macOS `Form { Section { ... } }`, which is a light surface. The new styles use
`Color.white`-based foreground and background opacities tuned for dark
materials; forcing them onto Settings would produce white text on a light
background. Settings keeps its native button styling for this iteration. If
we ever decide to fully theme Settings, we either (a) add a light-aware
variant of `SecondaryButtonStyle` or (b) reskin Settings off `Form`.

## Constraints / notes

- **Disabled state** must respond to `@Environment(\.isEnabled)`. SwiftUI's
  `.disabled(...)` modifier flows into that environment value; our style
  reads it directly.
- **Hover tracking** uses `.onHover { ... }` per instance. Multiple buttons
  in the same row track independently.
- **Reduced motion:** wrap the slide-arrow and scale animations in
  `@Environment(\.accessibilityReduceMotion)`-aware logic — when reduce-motion
  is on, skip the slide and the 0.98 scale; keep color transitions.
- **Color in light vs dark:** the app currently runs in dark surfaces
  (`VisualEffectView(material: .popover)`, `.hudWindow`). The white-opacity
  values above are tuned for dark. If a light surface gets these buttons later
  we revisit; for now, every callsite in the mapping sits on a dark material,
  so we don't add a light-mode pathway in this round.
- **Native shortcuts:** Don't reimplement keyboard handling. `Button` continues
  to handle ⏎ / esc / `keyboardShortcut`. The custom style is purely visual.

## Files touched

- **New:** `Sources/NudgeAI/Shared/AppButtonStyles.swift`
- **Edit:** `Sources/NudgeAI/Input/InstructionPanelView.swift`
- **Edit:** `Sources/NudgeAI/Controls/SessionHUDView.swift`
- **Edit:** `Sources/NudgeAI/Library/LibraryView.swift`
- **Edit:** `Sources/NudgeAI/Review/ReviewView.swift`
- ~~Edit: `Sources/NudgeAI/Settings/SettingsView.swift`~~ — skipped; see Settings note above.

## Verification

After each edit:

1. `make dev` (per project convention) — compile and refresh `NudgeAI.app/`.
2. Launch the app and exercise each surface that was changed:
   - Trigger a Nudge session → see HUD + InstructionPanel buttons in default
     / hover / pressed states.
   - Open Library → exercise Send to… / Reveal / Delete.
   - Open Review → Copy to Clipboard / Close.
   - Open Settings → each utility button + the disabled state on Reset.
3. Confirm disabled states actually look disabled (hotkey-recorder Reset
   when hotkey is off; Reset (sessions folder) when default; Next while editor
   is empty is *not* disabled today — leave that behaviour alone).

This is a native macOS app, so the "screenshot every web UI change" rule
does not apply. Verification is a manual visual pass.

## Out of scope

- A destructive (red) primary style.
- Light-mode tuning of colors.
- Tooltip / `.help(...)` content changes.
- Changing keyboard shortcuts or `.keyboardShortcut(...)` bindings.
- Animating the disabled→enabled transition.

## Memory follow-up

Update `feedback_button_style.md` to reflect the new direction (custom
`PrimaryButtonStyle` + `SecondaryButtonStyle` in `Sources/NudgeAI/Shared/`
are the canonical pattern). Done as part of the final commit, not before
implementation.
