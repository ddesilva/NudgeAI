# Nudge AI

A menu-bar macOS app to highlight regions of your screen and attach instructions
for a coding agent (Claude Code / Codex) to act on.

**Flow:** Start a session → drag a box around a region → a floating panel pops up
next to it → type what you want changed → press ⏎ → it auto-rearms for the next
box. When you're done, hit **Done** on the floating control (or the menu bar) to
open a **Review** window where you can preview every capture, edit/reorder/delete
instructions, then **Export & Copy**.

## What a session produces

A timestamped folder in `~/NudgeAISessions/Nudge-<date>/` (the location is
configurable in Settings):

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

## First-run permission

Nudge AI needs **Screen Recording** to capture regions. On first capture it will
prompt and/or open **System Settings ▸ Privacy & Security ▸ Screen Recording** —
enable **Nudge AI**, then quit and reopen the app. Nudge AI is a **menu-bar app
with no Dock icon** — after launch, look for the viewfinder icon in your menu
bar (top-right of the screen).

## Install

Download the latest signed + notarized `.dmg` from
[Releases](https://github.com/ddesilva/NudgeAI/releases), open it, and drag
**Nudge AI** to your Applications folder.
