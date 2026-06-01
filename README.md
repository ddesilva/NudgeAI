# Nudge AI

A menu-bar macOS app to highlight regions of your screen and attach instructions
for a coding agent (Claude Code / Codex) to act on.

**Flow:** Start a session → drag a box around a region → a floating panel pops up
next to it → type what you want changed → press ⏎ → it auto-rearms for the next
box. When you're done, hit **Done** on the floating control (or the menu bar) to
open a **Review** window where you can preview every capture, edit/reorder/delete
instructions, then **Export & Copy**.

## What a session produces

A timestamped folder in `~/NudgeAISessions/Nudge-<date>/`:

- `shot-01.png`, `shot-02.png`, … — the captured regions (Retina-resolution)
- `instructions.md` — each screenshot paired with its instruction
- `nudge.json` — machine-readable manifest (files, instructions, pixel sizes)

On export, a **paste-ready prompt** (referencing the absolute image paths) is
copied to your clipboard — ideal for terminal agents like Claude Code / Codex,
which read the image files from disk.

### Why not "everything on the clipboard"?

macOS can't reliably paste N images + matching text in one go: terminals can't
accept pasted images at all, and chat apps take only one image per paste. So the
session **folder** is the real artifact — point your agent at it (or paste the
copied prompt). The Review window is your visual preview before exporting.

## Build & run (no full Xcode needed)

```bash
cd ~/Projects/Cue
./build.sh            # builds release + assembles NudgeAI.app + ad-hoc signs
open NudgeAI.app
```

For fast iteration during development:

```bash
swift build           # debug build
swift run NudgeAI     # run straight from SwiftPM (menu-bar icon appears)
```

> Running via `swift run` works, but **Screen Recording permission attaches to a
> bundle**, so for real use build `NudgeAI.app` and run that.

## First-run permission

Nudge AI needs **Screen Recording** to capture regions. On first capture it will
prompt and/or open **System Settings ▸ Privacy & Security ▸ Screen Recording** —
enable **Nudge AI**, then quit and reopen the app.

> Note: ad-hoc signing changes on every rebuild, so macOS may ask you to
> re-grant Screen Recording after a rebuild. Keep `NudgeAI.app` in a stable
> location (e.g. `/Applications`) to minimize this.

## Project layout

```
Sources/NudgeAI/
  App.swift                         NSApplication bootstrap (accessory app)
  AppDelegate.swift
  SessionController.swift           Orchestrates capture → instruction → review
  Models.swift                      Annotation model
  Capture/CaptureService.swift      Permission + region capture (CGWindowList)
  Overlay/SelectionView.swift       Drag-to-select view (dim + hole punch)
  Overlay/SelectionOverlayController.swift   Full-screen overlay window
  Input/InstructionPanelController.swift     Floating instruction panel
  Controls/FloatingControlController.swift   Session HUD (Add / Done / Cancel)
  Controls/MenuBarController.swift           Status item + menu
  Review/ReviewView.swift           SwiftUI preview/edit list
  Review/ReviewWindowController.swift
  Export/Exporter.swift             Folder + markdown + json + clipboard
```

## Roadmap ideas

- Global hotkeys (Carbon `RegisterEventHotKey`) for start/box/end
- Migrate capture to ScreenCaptureKit (`SCScreenshotManager`, macOS 14+)
- Per-display capture for mixed-DPI setups
- Optional annotations drawn directly on the screenshot (arrows, numbers)
- "Send straight to Claude Code" integration
