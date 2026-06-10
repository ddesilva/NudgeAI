# NudgeAI v0.3 — Plan & Verify Pivot

**Status:** Draft for review
**Date:** 2026-06-10
**Supersedes:** `2026-06-08-nudgeai-loop-workspace-design.md` (v0.2 Loop Workspace)

## Problem

v0.2 embedded a terminal, an agent autolaunch loop, and a session library inside
NudgeAI. The bet was that NudgeAI would *be* the place you run the LLM.

The new bet is the opposite: you code in whatever terminal you already use
(Claude Code, Codex, plain shell). NudgeAI is a sidecar that two slash commands
talk to:

- `/nudgeai-plan` — render an HTML plan, let the user mark up lines and chat,
  ship the refinement back to the originating LLM.
- `/nudgeai-verify` — load a URL, let the user annotate it (capture-style boxes
  + instructions in V1; click-to-tweak CSS in V2), ship the change list back.

This pivot deletes the v0.2 workspace surface entirely and adds a new dock-icon
companion app.

## Goals (V1)

1. External terminals stay external. No embedded PTY, no agent autolaunch.
2. A new `NudgeAI Workspace.app` (dock icon) renders HTML plans and URLs in
   tabs, one tab per active slash-command session.
3. `/nudgeai-plan` and `/nudgeai-verify` work as Claude Code skills and as a
   generic `nudgeai` shell binary.
4. Plan flow: line selection + chat composer → refinement payload returned to
   the originating LLM as the slash command's tool output.
5. Verify flow (capture mode): drag-to-box + per-box instructions on the live
   page → change list (rect + instruction + screenshot) returned to the LLM.
6. The existing menu-bar `NudgeAI.app` (⌘⇧N capture flow) ships unchanged.

## Non-goals (V1)

- Tweak-mode in verify (click-to-edit CSS). Button visible, behind "Coming
  soon" panel. Deferred to V2.
- Codex CLI skill. Bridge protocol supports it; the skill itself is deferred.
- Auto-detecting the active browser URL via AppleScript. V1 requires
  `/nudgeai-verify <url>`.
- Library entries for plan/verify sessions. Captures library unchanged.
- Authentication / non-loopback access to the HTTP bridge.

## Architecture

```
┌─────────────────────────────────────────┐
│        Your terminal (any shell)         │
│   Claude Code / Codex / shell            │
│   /nudgeai-plan   /nudgeai-verify        │
└────────────┬────────────────────────────┘
             │ HTTP (127.0.0.1:47291)
             ▼
┌─────────────────────────────────────────┐
│       NudgeAI Workspace.app (dock)       │
│   Local HTTP server (Network.framework)  │
│   Tabbed window: Plan tabs, Verify tabs  │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│   NudgeAI.app (menu-bar, unchanged)      │
│   ⌘⇧N capture → review → export          │
└─────────────────────────────────────────┘
```

Two separate macOS app bundles ship from the same repo. They share no runtime
state. The menu-bar app is the existing v0.1.x product (capture, review,
export). The Workspace app is a new target.

### Communication model

Each slash command:
1. Health-checks `GET /health`.
2. POSTs the session spec to `/sessions/plan` or `/sessions/verify`.
3. Long-polls `GET /sessions/{id}/refinement` (server holds open up to 600s).
4. When the user clicks **Send** in the Workspace UI, the long-poll resolves
   with the refinement JSON.
5. Slash command prints the JSON as its tool output. In Claude Code / Codex
   this becomes the LLM's next input. In `nudgeai` shell mode it prints to
   stdout.

Each refinement is one slash-command invocation. The session ID is
deterministic (`sha1(repoRoot + ":" + branch + ":" + planPath_or_url)[:12]`),
so re-invoking the slash command on the same plan focuses the same tab rather
than opening a duplicate.

## Deletion plan (v0.2 → v0.3)

### Files deleted

- `Sources/NudgeAI/Workspace/` — entire directory (15 files, ~1k lines):
  `AgentConfig.swift`, `AgentConfigEditorView.swift`, `AgentConfigStore.swift`,
  `LoopSessionRecord.swift`, `LoopSessionStore.swift`,
  `NewLoopSessionDialog.swift`, `PtyProcess.swift`, `TerminalPane.swift`,
  `WorkspaceRenderPaneView.swift`, `WorkspaceSession.swift`,
  `WorkspaceSessionsModel.swift`, `WorkspaceStatusRowView.swift`,
  `WorkspaceTabStripView.swift`, `WorkspaceView.swift`,
  `WorkspaceWindowController.swift`.
- `Sources/NudgeAI/Send/AgentSessionDetector.swift`.

### Files edited

- `Sources/NudgeAI/Controls/MenuBarController.swift` — remove "Open Session
  Workspace…" entry and ⌘W binding.
- `Sources/NudgeAI/Library/LibraryView.swift`,
  `Sources/NudgeAI/Library/SavedSession.swift` — revert to captures-only,
  drop the `LibrarySession` discriminated union.
- `Sources/NudgeAI/Send/SendToPickerView.swift`,
  `Sources/NudgeAI/Send/SendDispatcher.swift` — remove agent terminal rows.
  (Exact scope to be confirmed when reading these in plan phase; if any
  agent-coupled code remains useful for non-agent recipients, preserve it.)
- `Package.swift`, `Package.resolved` — drop the SwiftTerm dependency.
- `README.md` — drop workspace section, keep capture flow docs.

### What stays untouched

`Capture/`, `Overlay/`, `Input/`, `Review/`, `Export/`, `Settings/`,
`SessionController.swift`, the non-agent parts of `Send/`, and the captures
side of `Library/`.

## New target — `NudgeAI Workspace.app`

### Package.swift

A new executable target alongside the existing `NudgeAI` target. Bundle ID
`com.nudgeai.workspace`, `LSUIElement=false` (dock icon visible). No external
dependencies — uses `Network.framework`, `WebKit`, `AppKit`, `SwiftUI`.

### File layout

```
Sources/NudgeAIWorkspace/
├── main.swift                        NSApplication bootstrap
├── Bridge/
│   ├── BridgeServer.swift            NWListener + HTTP/1.1 parser
│   ├── BridgeRouter.swift            URL → handler dispatch
│   ├── SessionStore.swift            sessionId → Session map
│   ├── Session.swift                 enum Session { plan, verify }
│   ├── PlanSession.swift             { id, planPath, html, originLLM, continuation }
│   └── VerifySession.swift           { id, url, mode, continuation }
├── UI/
│   ├── MainWindowController.swift    single window, NSTabViewController
│   ├── TabStripView.swift            one tab per session
│   ├── EmptyStateView.swift          shown when no sessions active
│   ├── Plan/
│   │   ├── PlanTabView.swift         WKWebView + chat sidebar
│   │   ├── PlanWebView.swift         line-numbering injection + selection bridge
│   │   ├── ChatSidebar.swift         message thread + composer
│   │   └── SelectionChip.swift       "lines 14–22" pill with clear button
│   └── Verify/
│       ├── VerifyTabView.swift       mode toggle + WKWebView + overlay
│       ├── CaptureModeOverlay.swift  drag-to-box + InstructionPanelView
│       └── TweakModeStub.swift       "Coming soon" panel (V2)
├── Shared/
│   └── InstructionPanelView.swift    shared with menu-bar app's Capture/
│                                     (final location — package product vs.
│                                     in-target copy — decided in plan phase)
└── Resources/
    └── plan-renderer.js              line-numbering + selection JS
```

`InstructionPanelView` is lifted (not duplicated) — extracted to a shared
location that both apps can import, or copied with a `// origin:` reference
comment if Swift Package targets make sharing awkward. Plan phase to decide.

### Window model

Single `NSWindow` per process; new sessions become tabs. Closing the last
tab leaves the empty-state view visible (port number + cURL hint). Closing
the window quits the app via standard `NSApplicationDelegate` behavior.

## Plan flow

### Slash-command path resolution

1. If `$1` is provided → use it.
2. Else `branch=$(git rev-parse --abbrev-ref HEAD)`, look for
   `docs/superpowers/plans/${branch}.html`.
3. Else: instruct the originating LLM to generate one to
   `docs/superpowers/plans/${branch}.html`, then re-resolve.

### Bridge request

```
POST /sessions/plan
Content-Type: application/json

{
  "sessionId": "ab12cd34ef56",
  "planPath": "/abs/path/to/plan.html",
  "branch": "prototype-next-level",
  "repoRoot": "/Users/.../NudgeAI",
  "originLLM": "claude-code"
}
```

`originLLM` is one of `"claude-code"`, `"codex"`, `"shell"`. Used only for
display labels on the tab (e.g. "from Claude Code").

### Rendering

`PlanWebView` loads the HTML in a `WKWebView` with
`loadFileURL(..., allowingReadAccessTo: planDir)`. JavaScript injected by the
app wraps each line element in `<span data-line="N">` (line numbering is
inferred from the source file's line breaks, not from the rendered DOM tree)
and installs a selection listener that posts `{startLine, endLine, excerpt}`
back to Swift via `WKScriptMessageHandler`.

`DispatchSource` file watcher on the plan path; on `.write` or `.rename`
events, the web view reloads. This is how the user sees the LLM's edits land
live after submitting a refinement.

### Chat sidebar

Vertical sidebar to the right of the web view. Components top-to-bottom:

1. **Thread.** Past refinements + LLM-edit acknowledgements (the latter are
   inferred from file-watcher events: "plan updated").
2. **Selection chip.** Shows `lines 14–22` if a selection is active, with an
   × to clear it. Hidden if no selection.
3. **Composer.** Multiline textarea, **Send** button. Send is enabled if
   either the textarea has content OR there's an active selection.

### Refinement payload

When the user clicks **Send**, the chat sidebar POSTs internally:

```
POST /internal/sessions/{id}/send-refinement
{
  "selection": { "startLine": 14, "endLine": 22, "excerpt": "..." } | null,
  "chat": "drop step 3, the migration runs in the same txn"
}
```

The bridge resolves the slash command's pending long-poll with:

```json
{
  "kind": "refinement",
  "selection": { "startLine": 14, "endLine": 22, "excerpt": "..." },
  "chat": "drop step 3, the migration runs in the same txn",
  "planPath": "docs/superpowers/plans/prototype-next-level.html"
}
```

The LLM already has the plan in context (it either generated it or just read
it to write into NudgeAI), so the payload deliberately omits the full plan
body. The LLM re-reads the file by path when it needs to edit.

### Multi-round refinement

Each refinement is one slash-command invocation. After the LLM responds, the
user runs `/nudgeai-plan` again to send the next refinement; the same session
ID resolves to the same tab. The Workspace app does not require the slash
command to be polling for the tab to stay open.

**Send when no slash command is polling.** If the user marks up the plan and
clicks Send while no `/nudgeai-plan` is currently long-polling (e.g. between
turns), the refinement is queued on the session. The next long-poll for that
session ID returns the queued refinement immediately instead of waiting. The
queue holds at most one refinement; a second Send before the next poll
overwrites the first (the UI warns "Replace queued refinement?"). This keeps
the slash-command-per-refinement model intact while letting the user mark up
on their own timeline.

## Verify flow

### Slash-command invocation

`/nudgeai-verify <url>` (URL is required in V1; auto-detect deferred).

```
POST /sessions/verify
{
  "sessionId": "...",
  "url": "http://localhost:3000/dashboard",
  "repoRoot": "...",
  "originLLM": "claude-code"
}
```

### Capture mode (V1)

`VerifyTabView` header bar: editable URL + reload, mode toggle
`[Capture] [Tweak]`, End session button.

The pane is a `WKWebView` navigated to the URL. A transparent overlay on top
intercepts pointer events. ⌘B toggles overlay off so the user can click
through to navigate the page itself.

Interaction (mirrors menu-bar capture):
- Drag → box.
- `InstructionPanelView` popover appears next to the box.
- Type instruction → ⏎ saves and rearms; ⌘⏎ saves and ships immediately.

For each box, capture:
- `rect` in CSS pixels.
- `instruction` text.
- `screenshotPath` — `WKWebView.takeSnapshot(...)` cropped to the rect,
  written to `~/Library/Caches/com.nudgeai.workspace/verify/<sessionId>/<n>.png`.

On Send, the long-poll resolves with:

```json
{
  "kind": "verify-capture",
  "url": "http://localhost:3000/dashboard",
  "items": [
    {
      "rect": [120, 240, 360, 180],
      "instruction": "this card overflows on iPad widths — needs flex-wrap",
      "screenshotPath": "/Users/.../verify/ab12.../01.png"
    }
  ]
}
```

The originating LLM reads screenshots straight from disk by the absolute
path (same pattern as today's menu-bar capture export).

### Tweak mode (V2, stubbed in V1)

In V1, the Tweak toggle shows a "Coming soon" panel. V2 will add:
- Click an element → highlight + selector panel.
- Adjust color / background / padding / radius / font-size / font-weight with
  live preview (CSS injected via `evaluateJavaScript`).
- On Send, ship a list of `{selector, property, from, to}` to the LLM.

## Bridge protocol

### Endpoints

| Method | Path | From | Purpose |
|---|---|---|---|
| `GET`  | `/health` | slash command preflight | `200 {"version":"0.3.0"}` |
| `POST` | `/sessions/plan` | slash command | Open/focus a plan tab |
| `POST` | `/sessions/verify` | slash command | Open/focus a verify tab |
| `GET`  | `/sessions/{id}/refinement` | slash command | Long-poll for next refinement |
| `POST` | `/sessions/{id}/end` | slash command | Mark session ended |
| `POST` | `/internal/sessions/{id}/send-refinement` | UI (in-process) | Resolve pending long-poll |

### Port

Fixed `127.0.0.1:47291` in V1. If the port is already bound at app launch,
the app shows an empty-state error with the conflict and an `lsof -i :47291`
hint. The app stays open so the user can quit and retry.

### Session ID

Deterministic: `sha1(repoRoot + ":" + branch + ":" + planPath_or_url)[:12]`.

### Long-poll semantics

- 600-second server-side timeout. On timeout, server responds
  `{"kind":"timeout"}` and the slash command re-polls.
- The server holds the request open with a Swift `CheckedContinuation` stored
  on the session.
- If a second long-poll arrives for a session that already has one waiting,
  the older one returns `{"kind":"superseded"}` and the new one takes over.

### Security boundary

- Loopback only (`127.0.0.1`, not `0.0.0.0`).
- No authentication in V1. The trust model is: anything that can hit
  127.0.0.1 on this Mac is already trusted with code execution.
- `PlanWebView` config: `javaScriptEnabled = true`,
  `allowFileAccessFromFileURLs = false`,
  `allowUniversalAccessFromFileURLs = false`. Plan files are user/LLM-authored
  from local terminals — not loaded from untrusted sources. Known risk if
  this ever changes.
- Verify webview loads arbitrary URLs (that's the feature); normal WKWebView
  trust model, same as Safari.

## Slash-command surfaces

### Claude Code skill

Shipped to `~/.claude/plugins/nudgeai/` on first launch of Workspace.app
(consent dialog). Layout:

```
~/.claude/plugins/nudgeai/
├── plugin.json
└── skills/
    ├── nudgeai-plan/SKILL.md
    └── nudgeai-verify/SKILL.md
```

`nudgeai-plan/SKILL.md`:

```markdown
---
name: nudgeai-plan
description: Open the current branch's HTML plan in NudgeAI Workspace for
  line-by-line refinement. Returns the user's refinement as your next input.
---

1. Resolve plan path: $1 if given; else docs/superpowers/plans/${branch}.html;
   else ask the model to generate one there.
2. Health check: curl -sf http://127.0.0.1:47291/health || error.
3. Compute sessionId: sha1 of "$repoRoot:$branch:$planPath", first 12 chars.
4. POST /sessions/plan with the session spec.
5. Long-poll GET /sessions/$sessionId/refinement with --max-time 700.
6. Print the JSON response as skill output.
```

`nudgeai-verify/SKILL.md` is the same shape, with `$1=URL` and the verify
endpoint.

### Generic `nudgeai` shell binary

A small Swift command-line target inside the Workspace bundle at
`NudgeAI Workspace.app/Contents/MacOS/nudgeai`. On first launch the app
offers to symlink it to `/usr/local/bin/nudgeai` (consent dialog, sudo prompt
if needed; falls back to printing PATH instructions).

Usage:

```
nudgeai plan [path]
nudgeai verify <url>
```

Both block on the long-poll and print the resulting JSON to stdout. Less
seamless than the Claude Code skill (no auto-injection into the next LLM
turn) but works in any terminal.

### Codex CLI skill (deferred)

The HTTP bridge supports a Codex skill identical in shape to the Claude Code
one. Implementation deferred to a follow-up release.

## Error handling

| Case | Behavior |
|---|---|
| Workspace.app not running | Slash command health-check fails: `❌ NudgeAI Workspace.app isn't running. Run: open -a "NudgeAI Workspace"`. Exits non-zero. |
| Port 47291 in use at app launch | Empty-state UI shows the conflict + `lsof -i :47291` hint. App stays open. |
| Plan file deleted mid-session | File watcher fires; tab shows "Plan file moved or deleted at `<path>`. Re-run /nudgeai-plan." Send disabled. |
| Plan file is invalid HTML | Renderer falls back to `<pre>` raw-source view. Line selection still works. |
| Verify URL unreachable | WKWebView shows native error page. Capture overlay still functional (user can drop boxes noting the failure). |
| Long-poll connection drops | Slash command retries 3× with backoff, then errors out. |
| User closes window with active sessions | Confirm: "N active session(s) will be ended. Close anyway?" → on confirm, all pending polls resolve with `{"kind":"ended"}`. |
| User closes a single tab | That session's pending poll resolves with `{"kind":"ended"}`. |
| Two long-polls for same session | Older resolves with `{"kind":"superseded"}`; newer takes over. |

## Testing

### Unit (XCTest, no UI)

- `BridgeRouter` route matching + body parsing.
- `SessionStore` ID dedup, supersede semantics, end-of-session cleanup.
- `PlanSession` continuation lifecycle (start → resolve → re-poll).
- Refinement payload JSON shape, round-trip serialization.

### Integration

- Launch app in a test harness, hit endpoints with `URLSession`. Assert tab
  opens (accessibility inspection or `NSWorkspace`-level check).
- End-to-end: spawn app → POST plan → simulate Send via the internal
  endpoint → assert the long-poll returns the expected JSON.

### Manual smoke

Replaces the v0.2 smoke checklist (`docs/v0.2-smoke.md` if present):

- `nudgeai plan` happy path: existing file render, generate-new fallback,
  refinement round-trip with selection, refinement round-trip without
  selection.
- `nudgeai verify` capture mode: drag boxes, instructions persist, screenshots
  land in the per-session temp dir, JSON ships to stdout.
- Multi-session: two terminals, two plans, two tabs. Each refinement returns
  to its own slash command.
- Restart Workspace mid-poll: slash command's retry kicks in, resumes cleanly.
- Re-invoke `/nudgeai-plan` on the same plan: focuses existing tab, doesn't
  open a duplicate.

### Out of scope for V1 tests

- Tweak mode (deferred feature).
- Codex skill (deferred).
- HTML rendering fidelity beyond "line numbers + selection work".

## Sequencing

Suggested PR cuts (firmed up in the implementation plan):

1. **Demolition** — delete `Workspace/`, `Send/AgentSessionDetector.swift`,
   workspace menu entries, SwiftTerm dep. Captures app builds and ships.
2. **Bridge server scaffold** — new target, `NWListener` HTTP server,
   `/health` only, empty-state UI.
3. **Plan flow** — `POST /sessions/plan`, plan tab, line selection, chat
   sidebar, long-poll, file watcher.
4. **Verify flow (capture mode)** — `POST /sessions/verify`, verify tab,
   overlay, screenshots, payload.
5. **Slash-command surfaces** — Claude Code skill files, generic `nudgeai`
   binary, first-launch installer for both.
6. **README + smoke checklist** — refresh docs.

Each PR is independently shippable; demolition PR is the only one that
changes user-visible behavior in the existing app (removes the workspace
menu entry).

## Risks and known limits

- **Fixed port (47291).** Conflict requires manual resolution. Acceptable
  given the user trust model; revisit if conflicts come up in practice.
- **Plan HTML is rendered with JS enabled.** Plan files are local
  user/LLM-authored — not loaded from untrusted sources. If that changes,
  add a CSP sandbox layer.
- **Refinement payload deliberately omits the full plan body.** Assumes the
  originating LLM still has the plan in context. If a refinement comes in
  many turns later and the plan has rolled out of context, the LLM will
  re-read the file by path — slower but correct.
- **InstructionPanelView reuse across two app targets.** Either share via a
  third Swift Package product or copy with an origin reference. Plan phase
  decides.
- **Two separate apps to launch.** User has to remember that
  `NudgeAI Workspace.app` is a separate app from the menu-bar one. The
  first-launch installer + a Settings entry in the menu-bar app linking to
  the Workspace app should make this discoverable.

## Open questions for the implementation plan

- Exact reuse strategy for `InstructionPanelView` (shared package product
  vs. copy).
- Whether the generic `nudgeai` binary lives inside the Workspace app
  bundle or as a separate Swift Package executable.
- Whether the Workspace app should also offer to install a Codex skill stub
  now (no-op) so V2 ships without a re-install dance.
