# NudgeAI v0.3 Plan & Verify Pivot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pivot NudgeAI away from the v0.2 embedded loop workspace. Keep the existing menu-bar capture app unchanged; add a dock-icon `NudgeAI Workspace.app` with a local HTTP bridge that `/nudgeai-plan` and `/nudgeai-verify` slash commands talk to from any external terminal.

**Architecture:** Two macOS app targets in one Swift package — `NudgeAI` (existing menu-bar) and `NudgeAIWorkspace` (new dock app). The Workspace app runs a local HTTP server on `127.0.0.1:47291` (built on `Network.framework`, no third-party deps). Slash commands are thin curl wrappers; the originating LLM gets the user's refinement back as the slash command's tool output. A small `nudgeai` shell binary mirrors the slash commands for non-Claude-Code terminals.

**Tech Stack:** Swift 6, AppKit + SwiftUI, WebKit (WKWebView), Network.framework (NWListener), XCTest. Bash for slash-command skill bodies. No third-party Swift dependencies.

**Spec:** `docs/superpowers/specs/2026-06-10-nudgeai-plan-verify-pivot-design.md`

---

## File Structure

### Files deleted

```
Sources/NudgeAI/Workspace/                            ← entire directory (15 files)
Sources/NudgeAI/Send/                                 ← entire directory (4 files, replaces picker with direct clipboard)
```

### Files modified

```
Sources/NudgeAI/Controls/MenuBarController.swift      ← drop workspace menu entry
Sources/NudgeAI/Library/LibraryView.swift             ← revert to captures-only
Sources/NudgeAI/Library/SavedSession.swift            ← drop LibrarySession enum + extension
Sources/NudgeAI/SessionController.swift               ← replace picker with copyPromptToClipboard
Sources/NudgeAI/Library/LibraryWindowController.swift ← same
Sources/NudgeAI/Review/ReviewWindowController.swift   ← same
Package.swift                                          ← drop SwiftTerm, add NudgeAIWorkspace target
README.md                                              ← drop workspace section
```

### Files created (NudgeAIWorkspace target)

```
Sources/NudgeAIWorkspace/
├── main.swift                                  NSApplication bootstrap
├── Info.plist                                  bundle metadata, LSUIElement=false
├── Bridge/
│   ├── BridgeServer.swift                      NWListener wrapper
│   ├── HTTPParser.swift                        HTTP/1.1 request parsing
│   ├── HTTPResponse.swift                      response builder
│   ├── BridgeRouter.swift                      method+path → handler
│   ├── SessionStore.swift                      sessionId → Session map
│   ├── Session.swift                           Session protocol + ID helpers
│   ├── PlanSession.swift                       plan-specific session state
│   ├── VerifySession.swift                     verify-specific session state
│   ├── RefinementPayload.swift                 outgoing JSON payloads
│   └── Continuation.swift                      pending long-poll wrapper
├── UI/
│   ├── AppDelegate.swift                       window lifecycle
│   ├── MainWindowController.swift              tabbed window
│   ├── EmptyStateView.swift                    SwiftUI, shown with no sessions
│   ├── Plan/
│   │   ├── PlanTabView.swift                   web view + chat sidebar
│   │   ├── PlanWebView.swift                   NSViewRepresentable around WKWebView
│   │   ├── PlanSelection.swift                 selection model
│   │   ├── ChatSidebar.swift                   message thread + composer
│   │   └── PlanFileWatcher.swift               DispatchSource on plan path
│   └── Verify/
│       ├── VerifyTabView.swift                 url bar + mode toggle + web view
│       ├── VerifyWebView.swift                 NSViewRepresentable around WKWebView
│       ├── CaptureModeOverlay.swift            drag-to-box + InstructionPanelView reuse
│       ├── TweakModeStub.swift                 "Coming soon" panel
│       └── BoxedAnnotation.swift               per-box model
├── Shared/
│   └── InstructionPanelView.swift              shared with menu-bar Capture/ (final location TBD)
├── CLI/
│   └── nudgeai.swift                           nudgeai shell binary (separate target)
└── Resources/
    └── plan-renderer.js                        injected into PlanWebView

Sources/NudgeAIWorkspace/Skills/                ← shipped in bundle, installed on first launch
├── plugin.json
├── nudgeai-plan/SKILL.md
└── nudgeai-verify/SKILL.md

Tests/NudgeAIWorkspaceTests/
├── HTTPParserTests.swift
├── BridgeRouterTests.swift
├── SessionStoreTests.swift
├── PlanSessionTests.swift
├── RefinementPayloadTests.swift
└── BridgeServerIntegrationTests.swift
```

---

## Conventions used in this plan

- All paths are absolute from repo root (`/Users/dilshandesilva/Projects/NudgeAI`).
- Build command after Swift changes is **always** `make dev` (writes `NudgeAI.app/` for the menu-bar app; the Workspace app target adds `NudgeAIWorkspace.app/` to the same Makefile target). The CLAUDE.md memory note `feedback_always_build.md` reinforces this — never just `swift build`.
- Test commands use Swift Package Manager: `swift test --filter <TestName>`.
- Every task ends with an explicit `git commit` step. Commits are small and frequent.
- Code blocks show **only the lines being added/changed**, with surrounding `// existing code...` markers where context matters.

---

## Phase 1 — Demolition

Goal: remove the entire v0.2 workspace surface and the agent-aware Send picker. The menu-bar capture app must still build, launch, and complete a capture → review → clipboard round-trip after this phase.

### Task 1.1: Delete the Workspace/ directory and drop SwiftTerm

**Files:**
- Delete: `Sources/NudgeAI/Workspace/` (15 files: AgentConfig.swift, AgentConfigEditorView.swift, AgentConfigStore.swift, LoopSessionRecord.swift, LoopSessionStore.swift, NewLoopSessionDialog.swift, PtyProcess.swift, TerminalPane.swift, WorkspaceRenderPaneView.swift, WorkspaceSession.swift, WorkspaceSessionsModel.swift, WorkspaceStatusRowView.swift, WorkspaceTabStripView.swift, WorkspaceView.swift, WorkspaceWindowController.swift)
- Modify: `Package.swift`

- [ ] **Step 1: Confirm no callers outside Workspace/ besides MenuBarController**

```bash
grep -rn "WorkspaceWindowController\|WorkspaceSessionsModel\|WorkspaceSession\|LoopSessionStore\|LoopSessionRecord\|AgentConfig\|PtyProcess\|TerminalPane" Sources/NudgeAI --include="*.swift" | grep -v "^Sources/NudgeAI/Workspace/"
```

Expected: only matches in `Sources/NudgeAI/Controls/MenuBarController.swift` (one line, `openWorkspace` selector calling `WorkspaceWindowController.shared.show()`) and possibly `Sources/NudgeAI/Library/` (the `LibrarySession.loop` case). Anything else, stop and surface before deleting.

- [ ] **Step 2: Delete the directory**

```bash
git rm -r Sources/NudgeAI/Workspace/
```

- [ ] **Step 3: Drop SwiftTerm dependency from Package.swift**

Replace the contents of `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NudgeAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NudgeAI",
            path: "Sources/NudgeAI"
        ),
        .testTarget(
            name: "NudgeAITests",
            dependencies: ["NudgeAI"],
            path: "Tests/NudgeAITests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 4: Delete Package.resolved so SwiftTerm pin is gone**

```bash
rm -f Package.resolved
```

The Workspace target will be added to `Package.swift` in Task 2.1; for now we want a clean baseline.

- [ ] **Step 5: Build — expect MenuBarController.swift error referencing WorkspaceWindowController**

```bash
make dev
```

Expected: build fails with `error: cannot find 'WorkspaceWindowController' in scope` in `Sources/NudgeAI/Controls/MenuBarController.swift`. (Task 1.2 fixes this.) **Do not commit yet — Task 1.2 finishes the change.**

### Task 1.2: Remove the workspace menu entry

**Files:**
- Modify: `Sources/NudgeAI/Controls/MenuBarController.swift` (lines 106–108 and line 190)

- [ ] **Step 1: Remove the menu entry block**

Delete lines 106–108 (the three lines for the `workspace` `NSMenuItem`):

```swift
        let workspace = NSMenuItem(title: "Open Session Workspace…", action: #selector(openWorkspace), keyEquivalent: "w")
        workspace.target = self
        menu.addItem(workspace)
```

Also delete line 190 (the `openWorkspace` selector):

```swift
    @objc private func openWorkspace() { WorkspaceWindowController.shared.show() }
```

- [ ] **Step 2: Build — confirm clean**

```bash
make dev
```

Expected: build succeeds. NudgeAI.app is regenerated.

- [ ] **Step 3: Launch the app, open the menu, confirm the workspace entry is gone**

```bash
open NudgeAI.app
```

Click the menu-bar icon (right-click for the menu). Expected: no "Open Session Workspace…" entry between "Browse Sessions…" and "Open Sessions Folder".

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
demolition: remove v0.2 Workspace surface and SwiftTerm dep

Deletes Sources/NudgeAI/Workspace/ entirely and the workspace menu entry
from MenuBarController. Package.swift drops the SwiftTerm dependency.
First step of the v0.3 pivot — Library still references LoopSessionRecord
(fixed in next commit).
EOF
)"
```

### Task 1.3: Revert Library to captures-only

**Files:**
- Modify: `Sources/NudgeAI/Library/SavedSession.swift` (lines 289–326)
- Modify: `Sources/NudgeAI/Library/LibraryView.swift`
- Test: `Tests/NudgeAITests/SavedSessionTests.swift` (may not exist yet; create if missing)

- [ ] **Step 1: Inspect LibraryView for LibrarySession usage**

```bash
grep -n "LibrarySession\|loadAllLibrarySessions\|\.capture\|\.loop" Sources/NudgeAI/Library/LibraryView.swift
```

Note every line that mentions `LibrarySession`, the `.capture` / `.loop` cases, or `loadAllLibrarySessions`. These all revert.

- [ ] **Step 2: Delete the LibrarySession enum + extension from SavedSession.swift**

Delete lines 289–326 (everything from `// MARK: - LibrarySession` to end of file). The file should end at line 287 (the close of `enum SessionStore { ... }`).

- [ ] **Step 3: Revert LibraryView.swift to use SavedSession directly**

In `Sources/NudgeAI/Library/LibraryView.swift`, replace every reference to `LibrarySession` with `SavedSession`, every `loadAllLibrarySessions()` call with `loadAll()`, and remove the `switch` on `.capture` / `.loop` cases — keeping only the capture-handling branch.

Concretely: any line of the form

```swift
@State private var sessions: [LibrarySession] = []
```

becomes

```swift
@State private var sessions: [SavedSession] = []
```

Any `switch session { case .capture(let s): ... ; case .loop(let r): ... }` becomes the inline capture body.

If the file proves more entangled than this, stop and read the whole file end-to-end before editing — do not partially revert.

- [ ] **Step 4: Build**

```bash
make dev
```

Expected: build succeeds.

- [ ] **Step 5: Launch, open Browse Sessions, confirm only captures show**

```bash
open NudgeAI.app
```

Menu-bar → "Browse Sessions…". Expected: list shows previously captured sessions only; no loop rows.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
library: revert to captures-only after v0.2 workspace removal

Drops the LibrarySession discriminated union and the loop-session rows from
LibraryView. Captures library is back to its v0.1.x shape.
EOF
)"
```

### Task 1.4: Delete the Send/ directory and switch callers to clipboard-only

**Files:**
- Delete: `Sources/NudgeAI/Send/` (4 files: AgentSessionDetector.swift, SendDispatcher.swift, SendToPickerController.swift, SendToPickerView.swift)
- Modify: `Sources/NudgeAI/SessionController.swift` (lines 17, 122–127)
- Modify: `Sources/NudgeAI/Library/LibraryWindowController.swift` (lines 10, 52–57)
- Modify: `Sources/NudgeAI/Review/ReviewWindowController.swift` (lines 9, 62–67)

The send-picker has no purpose once agent rows are removed (only fallback was clipboard). Every existing call site degrades to `Exporter.copyPromptToClipboard(prompt)` plus a status message.

- [ ] **Step 1: Read SessionController.swift around the picker block**

```bash
sed -n '110,135p' Sources/NudgeAI/SessionController.swift
```

This shows the picker invocation. Note the surrounding context — you'll preserve it minus the picker, replacing with a direct clipboard call.

- [ ] **Step 2: Replace the picker block in SessionController.swift**

Delete line 17:

```swift
    private var sendPicker: SendToPickerController?
```

Replace lines 122–127 (the picker invocation) with the direct clipboard equivalent. Concretely, find:

```swift
        let picker = SendToPickerController()
        // ... whatever lines call .show / set onPick ...
        _ = SendDispatcher.send(prompt: prompt, to: chosen)
```

and replace with:

```swift
        Exporter.copyPromptToClipboard(prompt)
```

Re-read the surrounding logic — if the picker block was inside a closure that needed to fire after the picker returned (showing a status banner, etc.), inline that follow-up directly since there's no longer an async picker step.

- [ ] **Step 3: Same revert in LibraryWindowController.swift**

Delete line 10:

```swift
    private var picker: SendToPickerController?
```

Replace lines 52–57 with `Exporter.copyPromptToClipboard(prompt)` (same pattern as Step 2).

- [ ] **Step 4: Same revert in ReviewWindowController.swift**

Delete line 9 and replace lines 62–67. Same pattern.

- [ ] **Step 5: Delete the Send/ directory**

```bash
git rm -r Sources/NudgeAI/Send/
```

- [ ] **Step 6: Build**

```bash
make dev
```

Expected: build succeeds with no warnings about unused imports.

- [ ] **Step 7: Smoke-test the capture → review → clipboard flow**

```bash
open NudgeAI.app
```

Trigger ⌘⇧N → drag a region → type instruction → ⏎ → ⌘⏎ to finish. Review window opens. Click the export button. Expected: prompt copied to clipboard (paste into a terminal to verify it contains the expected `I've highlighted regions...` body).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
send: remove agent picker, route export straight to clipboard

The send picker only had clipboard as a non-agent target — without agent
detection it has no choice to offer. SessionController, LibraryWindow, and
ReviewWindow now call Exporter.copyPromptToClipboard directly. Deletes
AgentSessionDetector.swift, SendDispatcher.swift, SendToPickerView.swift,
SendToPickerController.swift.
EOF
)"
```

### Task 1.5: Update README to drop workspace mentions

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read the README and find workspace sections**

```bash
grep -n "workspace\|Workspace\|loop\|Loop\|agent\|Agent" README.md
```

Note every line. Workspace and loop-session paragraphs are deleted; mentions of "Claude Code / Codex" in the context of *pasting into them* stay (that's the menu-bar capture flow, not the workspace).

- [ ] **Step 2: Edit README**

Remove the entire "Session Workspace" / "Loop sessions" / "Agent config" sections and their menu-shortcut rows in the keyboard table. Keep the original capture flow (⌘⇧N, drag, instruction, Review, Export & Copy Prompt).

The README will be revisited at the end of the project to add a `/nudgeai-plan` and `/nudgeai-verify` section.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: drop v0.2 workspace mentions from README"
```

### Task 1.6: Validate the demolition

**Files:** (validation only, no edits)

- [ ] **Step 1: Confirm tree is clean**

```bash
ls Sources/NudgeAI/
```

Expected: `Capture/`, `Controls/`, `Export/`, `Input/`, `Library/`, `Overlay/`, `Review/`, `Settings/`, `Shared/`, `SessionController.swift`. No `Send/`, no `Workspace/`.

- [ ] **Step 2: Run the full test suite**

```bash
swift test
```

Expected: pass (any test files that referenced Workspace types should be gone via git rm).

- [ ] **Step 3: Manual smoke — capture round trip**

```bash
open NudgeAI.app
```

⌘⇧N → drag → instruction → ⌘⏎ → Review → Export. Confirm the prompt is on the clipboard and the session folder is in `~/NudgeAISessions/`.

No commit — this task is verification only.

---

## Phase 2 — Bridge server scaffold

Goal: stand up the new `NudgeAIWorkspace` target with a local HTTP server on `127.0.0.1:47291`, a `/health` endpoint, and an empty-state window. The bridge protocol surface ships first so we can `curl` against it end-to-end before any UI complexity lands.

### Task 2.1: Add NudgeAIWorkspace executable target to Package.swift

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NudgeAIWorkspace/main.swift`
- Create: `Sources/NudgeAIWorkspace/Info.plist`

- [ ] **Step 1: Update Package.swift to add the new target**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NudgeAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NudgeAI",
            path: "Sources/NudgeAI"
        ),
        .executableTarget(
            name: "NudgeAIWorkspace",
            path: "Sources/NudgeAIWorkspace",
            exclude: ["Info.plist", "Skills"],
            resources: [
                .copy("Resources/plan-renderer.js")
            ]
        ),
        .testTarget(
            name: "NudgeAITests",
            dependencies: ["NudgeAI"],
            path: "Tests/NudgeAITests"
        ),
        .testTarget(
            name: "NudgeAIWorkspaceTests",
            dependencies: ["NudgeAIWorkspace"],
            path: "Tests/NudgeAIWorkspaceTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Create the placeholder main.swift**

`Sources/NudgeAIWorkspace/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)

let alert = NSAlert()
alert.messageText = "NudgeAI Workspace"
alert.informativeText = "Bridge server not yet implemented (Task 2.2)."
alert.runModal()
```

- [ ] **Step 3: Create Info.plist**

`Sources/NudgeAIWorkspace/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.nudgeai.workspace</string>
    <key>CFBundleName</key>
    <string>NudgeAI Workspace</string>
    <key>CFBundleDisplayName</key>
    <string>NudgeAI Workspace</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 4: Create empty resources directory placeholder**

```bash
mkdir -p Sources/NudgeAIWorkspace/Resources
echo "// will be populated in Task 3.4" > Sources/NudgeAIWorkspace/Resources/plan-renderer.js
mkdir -p Tests/NudgeAIWorkspaceTests
```

- [ ] **Step 5: Add a placeholder test so the test target compiles**

`Tests/NudgeAIWorkspaceTests/SmokeTests.swift`:

```swift
import XCTest

final class SmokeTests: XCTestCase {
    func testTrue() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 6: Build both targets**

```bash
swift build
swift test --filter NudgeAIWorkspaceTests.SmokeTests
```

Expected: both succeed. Smoke test passes.

- [ ] **Step 7: Update Makefile to also bundle NudgeAIWorkspace.app**

```bash
cat Makefile
```

Read the existing `dev` target. It currently produces `NudgeAI.app`. Extend it to also copy the `NudgeAIWorkspace` binary into `NudgeAIWorkspace.app/Contents/MacOS/NudgeAIWorkspace` with `Info.plist` next to it. If the Makefile is parameterized over a single app name, add a second mirrored target that builds the second app. Keep the change minimal — both `make dev` and `make` should produce both `.app` bundles.

- [ ] **Step 8: Build via make**

```bash
make dev
```

Expected: both `NudgeAI.app` and `NudgeAIWorkspace.app` exist at repo root.

- [ ] **Step 9: Launch the workspace app, confirm dock icon + placeholder dialog**

```bash
open NudgeAIWorkspace.app
```

Expected: dock icon appears (LSUIElement is false), placeholder alert shows "Bridge server not yet implemented".

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: add NudgeAIWorkspace executable target scaffold

New Swift Package target + Info.plist + Makefile entry produce a dock-icon
app bundle with a placeholder alert. Server logic lands in subsequent tasks.
EOF
)"
```

### Task 2.2: HTTPParser — parse a single HTTP/1.1 request from raw bytes

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/HTTPParser.swift`
- Create: `Tests/NudgeAIWorkspaceTests/HTTPParserTests.swift`

The bridge takes one request per connection (slash commands curl and disconnect). We don't need keep-alive, pipelining, chunked encoding, or compression — just `Method Path HTTP/1.1\r\nHeader: value\r\n\r\n[body]`.

- [ ] **Step 1: Write the failing tests**

`Tests/NudgeAIWorkspaceTests/HTTPParserTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class HTTPParserTests: XCTestCase {
    func testParsesGetWithoutBody() throws {
        let raw = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        let req = try HTTPParser.parse(raw)
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/health")
        XCTAssertEqual(req.headers["Host"], "127.0.0.1")
        XCTAssertTrue(req.body.isEmpty)
    }

    func testParsesPostWithJSONBody() throws {
        let body = #"{"sessionId":"abc"}"#
        let raw = Data("POST /sessions/plan HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\nContent-Type: application/json\r\n\r\n\(body)".utf8)
        let req = try HTTPParser.parse(raw)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/sessions/plan")
        XCTAssertEqual(String(data: req.body, encoding: .utf8), body)
    }

    func testRejectsMissingTerminator() {
        let raw = Data("GET /health HTTP/1.1\r\nHost: 127.0.0.1".utf8)
        XCTAssertThrowsError(try HTTPParser.parse(raw))
    }

    func testHeadersAreCaseInsensitive() throws {
        let raw = Data("GET / HTTP/1.1\r\ncontent-length: 0\r\n\r\n".utf8)
        let req = try HTTPParser.parse(raw)
        XCTAssertEqual(req.headers["Content-Length"], "0")
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
swift test --filter HTTPParserTests
```

Expected: `error: no such module 'HTTPParser'` or unresolved-symbol errors.

- [ ] **Step 3: Implement HTTPParser**

`Sources/NudgeAIWorkspace/Bridge/HTTPParser.swift`:

```swift
import Foundation

struct HTTPRequest {
    let method: String
    let path: String
    let headers: CaseInsensitiveHeaders
    let body: Data
}

struct CaseInsensitiveHeaders {
    private var storage: [String: String] = [:]
    subscript(key: String) -> String? {
        get { storage[key.lowercased()] }
        set { storage[key.lowercased()] = newValue }
    }
}

enum HTTPParserError: Error {
    case incompleteHeaders
    case malformedRequestLine
    case malformedHeader(String)
}

enum HTTPParser {
    static func parse(_ data: Data) throws -> HTTPRequest {
        let terminator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: terminator) else {
            throw HTTPParserError.incompleteHeaders
        }

        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        let body = data.subdata(in: headerEnd.upperBound..<data.count)

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw HTTPParserError.incompleteHeaders
        }

        let lines = headerString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { throw HTTPParserError.malformedRequestLine }

        let parts = firstLine.components(separatedBy: " ")
        guard parts.count == 3 else { throw HTTPParserError.malformedRequestLine }
        let method = parts[0]
        let path = parts[1]

        var headers = CaseInsensitiveHeaders()
        for line in lines.dropFirst() {
            guard !line.isEmpty else { continue }
            guard let colon = line.firstIndex(of: ":") else {
                throw HTTPParserError.malformedHeader(line)
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter HTTPParserTests
```

Expected: all four pass.

- [ ] **Step 5: Build the app**

```bash
make dev
```

Expected: succeeds.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "workspace: HTTPParser for one-shot HTTP/1.1 requests"
```

### Task 2.3: HTTPResponse — build response bytes

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/HTTPResponse.swift`
- Create: `Tests/NudgeAIWorkspaceTests/HTTPResponseTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/NudgeAIWorkspaceTests/HTTPResponseTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class HTTPResponseTests: XCTestCase {
    func testJSONResponseBytes() {
        let res = HTTPResponse.json(status: 200, body: #"{"ok":true}"#)
        let str = String(data: res.bytes(), encoding: .utf8) ?? ""
        XCTAssertTrue(str.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(str.contains("Content-Type: application/json"))
        XCTAssertTrue(str.contains("Content-Length: 11"))
        XCTAssertTrue(str.hasSuffix(#"{"ok":true}"#))
    }

    func testErrorMapping() {
        XCTAssertTrue(String(data: HTTPResponse.error(status: 404, message: "not found").bytes(), encoding: .utf8)!
            .hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        XCTAssertTrue(String(data: HTTPResponse.error(status: 400, message: "bad").bytes(), encoding: .utf8)!
            .hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
swift test --filter HTTPResponseTests
```

Expected: unresolved-symbol errors.

- [ ] **Step 3: Implement HTTPResponse**

`Sources/NudgeAIWorkspace/Bridge/HTTPResponse.swift`:

```swift
import Foundation

struct HTTPResponse {
    let status: Int
    let reason: String
    let headers: [(String, String)]
    let body: Data

    func bytes() -> Data {
        var s = "HTTP/1.1 \(status) \(reason)\r\n"
        for (k, v) in headers {
            s += "\(k): \(v)\r\n"
        }
        s += "Content-Length: \(body.count)\r\n"
        s += "Connection: close\r\n"
        s += "\r\n"
        var out = Data(s.utf8)
        out.append(body)
        return out
    }

    static func json(status: Int, body: String) -> HTTPResponse {
        HTTPResponse(
            status: status,
            reason: Self.reason(for: status),
            headers: [("Content-Type", "application/json")],
            body: Data(body.utf8)
        )
    }

    static func error(status: Int, message: String) -> HTTPResponse {
        json(status: status, body: #"{"error":"\#(message)"}"#)
    }

    private static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 408: return "Request Timeout"
        case 500: return "Internal Server Error"
        default:  return "Unknown"
        }
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
swift test --filter HTTPResponseTests
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "workspace: HTTPResponse builder with status text + Content-Length"
```

### Task 2.4: BridgeServer — bind 127.0.0.1:47291 and accept connections

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/BridgeServer.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`

This task uses `Network.framework` (`NWListener` over `.tcp`). Each accepted connection reads until headers complete + body satisfies `Content-Length`, dispatches to a handler closure, writes the response, and closes.

- [ ] **Step 1: Implement BridgeServer**

`Sources/NudgeAIWorkspace/Bridge/BridgeServer.swift`:

```swift
import Foundation
import Network

enum BridgeServerError: Error {
    case portInUse
    case bindFailed(String)
}

final class BridgeServer {
    typealias Handler = (HTTPRequest, @escaping (HTTPResponse) -> Void) -> Void

    private let port: NWEndpoint.Port
    private let queue: DispatchQueue
    private var listener: NWListener?
    private let handler: Handler

    init(port: UInt16 = 47291, handler: @escaping Handler) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.queue = DispatchQueue(label: "NudgeAIBridgeServer")
        self.handler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.requiredInterfaceType = .loopback

        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: port)
        } catch {
            throw BridgeServerError.bindFailed(error.localizedDescription)
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let err) = state {
                NSLog("BridgeServer listener failed: \(err)")
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        readRequest(conn, accumulated: Data())
    }

    private func readRequest(_ conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if let error {
                NSLog("BridgeServer recv error: \(error)")
                conn.cancel()
                return
            }
            var buf = accumulated
            if let chunk { buf.append(chunk) }

            if let req = self.tryParse(buf) {
                self.handler(req) { response in
                    let bytes = response.bytes()
                    conn.send(content: bytes, completion: .contentProcessed { _ in
                        conn.cancel()
                    })
                }
                return
            }

            if isComplete {
                conn.cancel()
                return
            }
            self.readRequest(conn, accumulated: buf)
        }
    }

    private func tryParse(_ data: Data) -> HTTPRequest? {
        guard let req = try? HTTPParser.parse(data) else { return nil }
        if let lenStr = req.headers["Content-Length"], let len = Int(lenStr), req.body.count < len {
            return nil
        }
        return req
    }
}
```

- [ ] **Step 2: Wire BridgeServer into main.swift for an end-to-end smoke**

Replace `Sources/NudgeAIWorkspace/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let server = BridgeServer { req, respond in
    if req.method == "GET" && req.path == "/health" {
        respond(.json(status: 200, body: #"{"version":"0.3.0"}"#))
    } else {
        respond(.error(status: 404, message: "not found"))
    }
}

do {
    try server.start()
    NSLog("BridgeServer listening on 127.0.0.1:47291")
} catch {
    NSLog("BridgeServer failed to start: \(error)")
}

app.activate(ignoringOtherApps: true)
app.run()
```

- [ ] **Step 3: Build and launch**

```bash
make dev
open NudgeAIWorkspace.app
```

- [ ] **Step 4: Curl /health from a separate terminal — expect 200**

```bash
curl -i http://127.0.0.1:47291/health
```

Expected:

```
HTTP/1.1 200 OK
Content-Type: application/json
Content-Length: 21
Connection: close

{"version":"0.3.0"}
```

- [ ] **Step 5: Curl an unknown path — expect 404**

```bash
curl -i http://127.0.0.1:47291/nope
```

Expected: `HTTP/1.1 404 Not Found` with `{"error":"not found"}` body.

- [ ] **Step 6: Confirm port is loopback only**

```bash
lsof -i :47291 -P
```

Expected: a line showing `NudgeAIWor` listening on `127.0.0.1:47291` (no `*:47291`).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: BridgeServer binds 127.0.0.1:47291 over Network.framework

NWListener with acceptLocalOnly + .loopback interface required. main.swift
wires a /health endpoint end-to-end; curl confirms 200 with version body.
EOF
)"
```

### Task 2.5: BridgeRouter — dispatch by method+path

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/BridgeRouter.swift`
- Create: `Tests/NudgeAIWorkspaceTests/BridgeRouterTests.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`

The router maps `(method, pathPattern)` to async handler closures and extracts path parameters like `{id}` from `/sessions/{id}/refinement`.

- [ ] **Step 1: Write the failing tests**

`Tests/NudgeAIWorkspaceTests/BridgeRouterTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class BridgeRouterTests: XCTestCase {
    func testStaticRouteMatches() async {
        var router = BridgeRouter()
        router.register(method: "GET", pattern: "/health") { _, _ in
            HTTPResponse.json(status: 200, body: "{}")
        }
        let req = makeRequest("GET", "/health")
        let res = await router.dispatch(req)
        XCTAssertEqual(res.status, 200)
    }

    func testParameterExtraction() async {
        var router = BridgeRouter()
        var captured: String?
        router.register(method: "GET", pattern: "/sessions/{id}/refinement") { _, params in
            captured = params["id"]
            return HTTPResponse.json(status: 200, body: "{}")
        }
        _ = await router.dispatch(makeRequest("GET", "/sessions/abc123/refinement"))
        XCTAssertEqual(captured, "abc123")
    }

    func testUnknownRouteIs404() async {
        let router = BridgeRouter()
        let res = await router.dispatch(makeRequest("GET", "/nope"))
        XCTAssertEqual(res.status, 404)
    }

    func testMethodMismatchIs404() async {
        var router = BridgeRouter()
        router.register(method: "POST", pattern: "/sessions/plan") { _, _ in
            HTTPResponse.json(status: 200, body: "{}")
        }
        let res = await router.dispatch(makeRequest("GET", "/sessions/plan"))
        XCTAssertEqual(res.status, 404)
    }

    private func makeRequest(_ method: String, _ path: String) -> HTTPRequest {
        HTTPRequest(method: method, path: path, headers: CaseInsensitiveHeaders(), body: Data())
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
swift test --filter BridgeRouterTests
```

- [ ] **Step 3: Implement BridgeRouter**

`Sources/NudgeAIWorkspace/Bridge/BridgeRouter.swift`:

```swift
import Foundation

struct BridgeRouter {
    typealias Handler = (HTTPRequest, [String: String]) async -> HTTPResponse

    private struct Route {
        let method: String
        let segments: [String]   // "{id}" stays literal, matched as wildcard
        let handler: Handler
    }

    private var routes: [Route] = []

    mutating func register(method: String, pattern: String, handler: @escaping Handler) {
        routes.append(Route(method: method, segments: split(pattern), handler: handler))
    }

    func dispatch(_ req: HTTPRequest) async -> HTTPResponse {
        let pathSegments = split(req.path)
        for route in routes where route.method == req.method {
            if let params = match(route: route, against: pathSegments) {
                return await route.handler(req, params)
            }
        }
        return .error(status: 404, message: "no route")
    }

    private func match(route: Route, against segments: [String]) -> [String: String]? {
        guard route.segments.count == segments.count else { return nil }
        var params: [String: String] = [:]
        for (pattern, actual) in zip(route.segments, segments) {
            if pattern.hasPrefix("{") && pattern.hasSuffix("}") {
                let key = String(pattern.dropFirst().dropLast())
                params[key] = actual
            } else if pattern != actual {
                return nil
            }
        }
        return params
    }

    private func split(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }
}
```

- [ ] **Step 4: Run — expect pass**

```bash
swift test --filter BridgeRouterTests
```

- [ ] **Step 5: Wire router into main.swift**

Replace the handler block in `main.swift`:

```swift
var router = BridgeRouter()
router.register(method: "GET", pattern: "/health") { _, _ in
    .json(status: 200, body: #"{"version":"0.3.0"}"#)
}

let server = BridgeServer { req, respond in
    Task {
        let res = await router.dispatch(req)
        respond(res)
    }
}
```

- [ ] **Step 6: Smoke — re-curl /health**

```bash
make dev
open NudgeAIWorkspace.app
curl -i http://127.0.0.1:47291/health
```

Expected: still 200.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "workspace: BridgeRouter dispatches by method+path with {id} params"
```

### Task 2.6: AppDelegate + MainWindowController + EmptyStateView

**Files:**
- Create: `Sources/NudgeAIWorkspace/UI/AppDelegate.swift`
- Create: `Sources/NudgeAIWorkspace/UI/MainWindowController.swift`
- Create: `Sources/NudgeAIWorkspace/UI/EmptyStateView.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`

The window is a single `NSWindow` hosting an `NSTabViewController`. With no sessions, the window shows `EmptyStateView`. New sessions become tabs in subsequent tasks; this task just stands the window up.

- [ ] **Step 1: AppDelegate**

`Sources/NudgeAIWorkspace/UI/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = MainWindowController()
        controller.showWindow(nil)
        self.windowController = controller
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 2: MainWindowController**

`Sources/NudgeAIWorkspace/UI/MainWindowController.swift`:

```swift
import AppKit
import SwiftUI

final class MainWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NudgeAI Workspace"
        window.center()

        let host = NSHostingController(rootView: EmptyStateView())
        window.contentViewController = host

        self.init(window: window)
    }
}
```

- [ ] **Step 3: EmptyStateView**

`Sources/NudgeAIWorkspace/UI/EmptyStateView.swift`:

```swift
import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Waiting for /nudgeai-plan or /nudgeai-verify…")
                .font(.title3)

            Text("Bridge listening on 127.0.0.1:47291")
                .font(.body.monospaced())
                .foregroundStyle(.secondary)

            Text("From any terminal:\n\(Self.curlHint)")
                .font(.callout.monospaced())
                .multilineTextAlignment(.leading)
                .padding(.top, 12)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private static let curlHint =
        "curl http://127.0.0.1:47291/health"
}
```

- [ ] **Step 4: Wire AppDelegate into main.swift**

Replace `Sources/NudgeAIWorkspace/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let delegate = AppDelegate()
app.delegate = delegate

var router = BridgeRouter()
router.register(method: "GET", pattern: "/health") { _, _ in
    .json(status: 200, body: #"{"version":"0.3.0"}"#)
}

let server = BridgeServer { req, respond in
    Task {
        let res = await router.dispatch(req)
        respond(res)
    }
}

do {
    try server.start()
    NSLog("BridgeServer listening on 127.0.0.1:47291")
} catch {
    NSLog("BridgeServer failed to start: \(error)")
    let alert = NSAlert()
    alert.messageText = "Port 47291 already in use"
    alert.informativeText = "Run `lsof -i :47291` to find the conflict, quit the offending process, then relaunch NudgeAI Workspace."
    alert.runModal()
}

app.activate(ignoringOtherApps: true)
app.run()
```

- [ ] **Step 5: Build and launch**

```bash
make dev
open NudgeAIWorkspace.app
```

Expected: window opens centered, shows "Waiting for /nudgeai-plan or /nudgeai-verify…" with the port + curl hint. Dock icon visible.

- [ ] **Step 6: Test port-conflict path**

In one terminal:

```bash
nc -l 127.0.0.1 47291 &
```

Then:

```bash
open NudgeAIWorkspace.app
```

Expected: alert reads "Port 47291 already in use". Click OK; window still appears (app doesn't crash). Kill the `nc`:

```bash
kill %1
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: AppDelegate + MainWindowController + EmptyStateView

Window opens centered showing the bridge port + curl hint. Port-conflict
path surfaces an alert and leaves the window visible so the user can debug.
EOF
)"
```

---

## Phase 3 — Plan flow

Goal: `POST /sessions/plan` opens a plan tab; long-poll resolves on Send; plan file changes hot-reload the web view.

### Task 3.1: Session models and session-ID derivation

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/Session.swift`
- Create: `Sources/NudgeAIWorkspace/Bridge/PlanSession.swift`
- Create: `Sources/NudgeAIWorkspace/Bridge/SessionStore.swift`
- Create: `Sources/NudgeAIWorkspace/Bridge/Continuation.swift`
- Create: `Tests/NudgeAIWorkspaceTests/SessionStoreTests.swift`

- [ ] **Step 1: Continuation wrapper**

`Sources/NudgeAIWorkspace/Bridge/Continuation.swift`:

```swift
import Foundation

/// A single-shot promise used by long-polls. The slash command's request
/// suspends on `await value()` until `resolve(_:)` is called from the UI.
actor PendingRefinement {
    private var continuation: CheckedContinuation<RefinementPayload, Never>?
    private var queued: RefinementPayload?
    private var resolved: RefinementPayload?

    func value() async -> RefinementPayload {
        if let queued {
            self.queued = nil
            return queued
        }
        return await withCheckedContinuation { cont in
            self.continuation = cont
        }
    }

    func resolve(_ payload: RefinementPayload) {
        if let continuation {
            continuation.resume(returning: payload)
            self.continuation = nil
        } else {
            queued = payload
        }
    }

    func supersede(with payload: RefinementPayload = .superseded) {
        if let continuation {
            continuation.resume(returning: payload)
            self.continuation = nil
        }
    }
}
```

- [ ] **Step 2: RefinementPayload skeleton**

Create a stub now; full schema lands in Task 3.6.

`Sources/NudgeAIWorkspace/Bridge/RefinementPayload.swift`:

```swift
import Foundation

struct RefinementPayload: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case refinement
        case verifyCapture = "verify-capture"
        case timeout
        case superseded
        case ended
    }

    let kind: Kind
    let selection: PlanSelection?
    let chat: String?
    let planPath: String?
    let url: String?
    let items: [VerifyItem]?

    static let timeout = RefinementPayload(kind: .timeout, selection: nil, chat: nil, planPath: nil, url: nil, items: nil)
    static let superseded = RefinementPayload(kind: .superseded, selection: nil, chat: nil, planPath: nil, url: nil, items: nil)
    static let ended = RefinementPayload(kind: .ended, selection: nil, chat: nil, planPath: nil, url: nil, items: nil)
}

struct PlanSelection: Codable, Equatable, Sendable {
    let startLine: Int
    let endLine: Int
    let excerpt: String
}

struct VerifyItem: Codable, Equatable, Sendable {
    let rect: [Double]   // [x, y, w, h]
    let instruction: String
    let screenshotPath: String
}
```

- [ ] **Step 3: Session protocol**

`Sources/NudgeAIWorkspace/Bridge/Session.swift`:

```swift
import Foundation
import CryptoKit

protocol Session: AnyObject {
    var id: String { get }
    var pending: PendingRefinement { get }
}

enum SessionID {
    static func make(repoRoot: String, branch: String, key: String) -> String {
        let raw = "\(repoRoot):\(branch):\(key)"
        let digest = Insecure.SHA1.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}
```

- [ ] **Step 4: PlanSession**

`Sources/NudgeAIWorkspace/Bridge/PlanSession.swift`:

```swift
import Foundation

final class PlanSession: Session {
    let id: String
    let planPath: String
    let repoRoot: String
    let branch: String
    let originLLM: String
    let pending = PendingRefinement()

    init(id: String, planPath: String, repoRoot: String, branch: String, originLLM: String) {
        self.id = id
        self.planPath = planPath
        self.repoRoot = repoRoot
        self.branch = branch
        self.originLLM = originLLM
    }
}
```

- [ ] **Step 5: SessionStore — write failing tests first**

`Tests/NudgeAIWorkspaceTests/SessionStoreTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class SessionStoreTests: XCTestCase {
    func testRegisterAndFetch() async {
        let store = SessionStore()
        let plan = PlanSession(id: "abc", planPath: "/p.html", repoRoot: "/r", branch: "main", originLLM: "claude-code")
        await store.upsert(plan)
        let fetched = await store.session(id: "abc")
        XCTAssertTrue(fetched as? PlanSession === plan)
    }

    func testSameIDDoesNotDuplicate() async {
        let store = SessionStore()
        let first = PlanSession(id: "abc", planPath: "/p.html", repoRoot: "/r", branch: "main", originLLM: "claude-code")
        await store.upsert(first)
        let second = PlanSession(id: "abc", planPath: "/p.html", repoRoot: "/r", branch: "main", originLLM: "claude-code")
        await store.upsert(second)
        let count = await store.allSessions().count
        XCTAssertEqual(count, 1)
        let resolved = await store.session(id: "abc")
        XCTAssertTrue(resolved as? PlanSession === first, "first registration wins; tab focuses existing")
    }

    func testDerivedIDIsDeterministic() {
        let a = SessionID.make(repoRoot: "/r", branch: "main", key: "/p.html")
        let b = SessionID.make(repoRoot: "/r", branch: "main", key: "/p.html")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 12)
    }
}
```

- [ ] **Step 6: Run — expect failure**

```bash
swift test --filter SessionStoreTests
```

- [ ] **Step 7: Implement SessionStore**

`Sources/NudgeAIWorkspace/Bridge/SessionStore.swift`:

```swift
import Foundation

actor SessionStore {
    private var byID: [String: Session] = [:]

    func upsert(_ session: Session) {
        if byID[session.id] == nil {
            byID[session.id] = session
        }
    }

    func session(id: String) -> Session? {
        byID[id]
    }

    func allSessions() -> [Session] {
        Array(byID.values)
    }

    func remove(id: String) {
        byID.removeValue(forKey: id)
    }
}
```

- [ ] **Step 8: Run — expect pass**

```bash
swift test --filter SessionStoreTests
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "workspace: session models, deterministic IDs, in-memory store"
```

### Task 3.2: POST /sessions/plan handler

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/PlanHandler.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`
- Create: `Tests/NudgeAIWorkspaceTests/PlanHandlerTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/NudgeAIWorkspaceTests/PlanHandlerTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class PlanHandlerTests: XCTestCase {
    func testValidPostCreatesSessionAndReturnsID() async {
        let store = SessionStore()
        let handler = PlanHandler(store: store, openTab: { _ in })
        let body = Data(#"{"sessionId":"abc","planPath":"/tmp/p.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}"#.utf8)
        let req = HTTPRequest(method: "POST", path: "/sessions/plan", headers: CaseInsensitiveHeaders(), body: body)

        let res = await handler.handle(req, params: [:])
        XCTAssertEqual(res.status, 200)
        XCTAssertEqual(await store.allSessions().count, 1)
    }

    func testInvalidJSONIs400() async {
        let store = SessionStore()
        let handler = PlanHandler(store: store, openTab: { _ in })
        let req = HTTPRequest(method: "POST", path: "/sessions/plan", headers: CaseInsensitiveHeaders(), body: Data("not json".utf8))
        let res = await handler.handle(req, params: [:])
        XCTAssertEqual(res.status, 400)
    }

    func testOpenTabCalledOnce() async {
        let store = SessionStore()
        let count = Counter()
        let handler = PlanHandler(store: store, openTab: { _ in await count.increment() })
        let body = Data(#"{"sessionId":"abc","planPath":"/tmp/p.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}"#.utf8)
        let req = HTTPRequest(method: "POST", path: "/sessions/plan", headers: CaseInsensitiveHeaders(), body: body)
        _ = await handler.handle(req, params: [:])
        XCTAssertEqual(await count.value, 1)
    }
}

actor Counter {
    var value = 0
    func increment() { value += 1 }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
swift test --filter PlanHandlerTests
```

- [ ] **Step 3: Implement PlanHandler**

`Sources/NudgeAIWorkspace/Bridge/PlanHandler.swift`:

```swift
import Foundation

struct PlanHandlerRequest: Codable {
    let sessionId: String
    let planPath: String
    let branch: String
    let repoRoot: String
    let originLLM: String
}

struct PlanHandler {
    let store: SessionStore
    let openTab: (PlanSession) async -> Void

    func handle(_ req: HTTPRequest, params: [String: String]) async -> HTTPResponse {
        guard let body = try? JSONDecoder().decode(PlanHandlerRequest.self, from: req.body) else {
            return .error(status: 400, message: "invalid request body")
        }
        let session = PlanSession(
            id: body.sessionId,
            planPath: body.planPath,
            repoRoot: body.repoRoot,
            branch: body.branch,
            originLLM: body.originLLM
        )
        await store.upsert(session)
        if let existing = await store.session(id: body.sessionId) as? PlanSession {
            await openTab(existing)
        }
        return .json(status: 200, body: #"{"sessionId":"\#(body.sessionId)"}"#)
    }
}
```

- [ ] **Step 4: Run — expect pass**

```bash
swift test --filter PlanHandlerTests
```

- [ ] **Step 5: Register the route in main.swift**

Inside the router setup block in `main.swift`, add (after the existing `/health` registration):

```swift
let store = SessionStore()
let openTab: (PlanSession) async -> Void = { session in
    await MainActor.run {
        delegate.windowController?.openPlanTab(for: session)
    }
}

let planHandler = PlanHandler(store: store, openTab: openTab)
router.register(method: "POST", pattern: "/sessions/plan") { req, params in
    await planHandler.handle(req, params: params)
}
```

`openPlanTab(for:)` is a stub on `MainWindowController` for now; Task 3.4 fills it in.

- [ ] **Step 6: Stub the MainWindowController method**

In `Sources/NudgeAIWorkspace/UI/MainWindowController.swift`, add:

```swift
func openPlanTab(for session: PlanSession) {
    NSLog("openPlanTab: \(session.id) at \(session.planPath)")
}
```

- [ ] **Step 7: Build, launch, smoke-test the endpoint**

```bash
make dev
open NudgeAIWorkspace.app
curl -i -X POST http://127.0.0.1:47291/sessions/plan \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"abc","planPath":"/tmp/p.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}'
```

Expected: 200 with `{"sessionId":"abc"}` body. The Workspace app's console shows `openPlanTab: abc at /tmp/p.html`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "workspace: POST /sessions/plan creates session + calls openTab stub"
```

### Task 3.3: GET /sessions/{id}/refinement long-poll

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/RefinementHandler.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`
- Create: `Tests/NudgeAIWorkspaceTests/RefinementHandlerTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/NudgeAIWorkspaceTests/RefinementHandlerTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class RefinementHandlerTests: XCTestCase {
    func testResolvesWhenSendArrives() async {
        let store = SessionStore()
        let plan = PlanSession(id: "abc", planPath: "/p", repoRoot: "/r", branch: "m", originLLM: "claude-code")
        await store.upsert(plan)
        let handler = RefinementHandler(store: store, timeout: .seconds(5))

        let pollTask = Task {
            await handler.handle(
                HTTPRequest(method: "GET", path: "/sessions/abc/refinement", headers: CaseInsensitiveHeaders(), body: Data()),
                params: ["id": "abc"]
            )
        }

        try? await Task.sleep(for: .milliseconds(50))
        let payload = RefinementPayload(kind: .refinement, selection: nil, chat: "hi", planPath: "/p", url: nil, items: nil)
        await plan.pending.resolve(payload)

        let res = await pollTask.value
        XCTAssertEqual(res.status, 200)
        let returnedKind = try? JSONDecoder().decode(RefinementPayload.self, from: res.body).kind
        XCTAssertEqual(returnedKind, .refinement)
    }

    func testReturnsTimeoutKindAfterTimeout() async {
        let store = SessionStore()
        let plan = PlanSession(id: "abc", planPath: "/p", repoRoot: "/r", branch: "m", originLLM: "claude-code")
        await store.upsert(plan)
        let handler = RefinementHandler(store: store, timeout: .milliseconds(100))

        let res = await handler.handle(
            HTTPRequest(method: "GET", path: "/sessions/abc/refinement", headers: CaseInsensitiveHeaders(), body: Data()),
            params: ["id": "abc"]
        )
        XCTAssertEqual(res.status, 200)
        let kind = try? JSONDecoder().decode(RefinementPayload.self, from: res.body).kind
        XCTAssertEqual(kind, .timeout)
    }

    func testUnknownSessionIs404() async {
        let store = SessionStore()
        let handler = RefinementHandler(store: store, timeout: .seconds(1))
        let res = await handler.handle(
            HTTPRequest(method: "GET", path: "/sessions/nope/refinement", headers: CaseInsensitiveHeaders(), body: Data()),
            params: ["id": "nope"]
        )
        XCTAssertEqual(res.status, 404)
    }
}
```

- [ ] **Step 2: Run — expect failure**

```bash
swift test --filter RefinementHandlerTests
```

- [ ] **Step 3: Implement RefinementHandler**

`Sources/NudgeAIWorkspace/Bridge/RefinementHandler.swift`:

```swift
import Foundation

struct RefinementHandler {
    let store: SessionStore
    let timeout: Duration

    func handle(_ req: HTTPRequest, params: [String: String]) async -> HTTPResponse {
        guard let id = params["id"], let session = await store.session(id: id) else {
            return .error(status: 404, message: "unknown session")
        }

        let payload: RefinementPayload = await withTaskGroup(of: RefinementPayload.self) { group in
            group.addTask { await session.pending.value() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return .timeout
            }
            let first = await group.next() ?? .timeout
            group.cancelAll()
            return first
        }

        let data = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        return HTTPResponse(
            status: 200,
            reason: "OK",
            headers: [("Content-Type", "application/json")],
            body: data
        )
    }
}
```

Note: the response's encoder uses default JSON encoding; the `Kind` enum's `verifyCapture = "verify-capture"` raw value gets serialized correctly because Swift's `Codable` uses raw values for `RawRepresentable` enums.

- [ ] **Step 4: Run — expect pass**

```bash
swift test --filter RefinementHandlerTests
```

- [ ] **Step 5: Register the route in main.swift**

Add (next to `planHandler` registration):

```swift
let refinementHandler = RefinementHandler(store: store, timeout: .seconds(600))
router.register(method: "GET", pattern: "/sessions/{id}/refinement") { req, params in
    await refinementHandler.handle(req, params: params)
}
```

- [ ] **Step 6: Smoke — long-poll from two terminals**

Terminal A:

```bash
make dev
open NudgeAIWorkspace.app
curl -i -X POST http://127.0.0.1:47291/sessions/plan \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"abc","planPath":"/tmp/p.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}'
```

Terminal B (starts the long-poll, will hang for now):

```bash
curl -N --max-time 5 http://127.0.0.1:47291/sessions/abc/refinement
```

Expected: after ~5 seconds (we set --max-time 5 on the client, not the server timeout), curl returns with `{"kind":"timeout",...}` (server emitted it at the 5 s mark via our test value? — adjust: for this manual smoke, temporarily set `RefinementHandler` timeout to `.seconds(3)`, smoke, then restore to 600. Or run a parallel POST internally — covered in Task 3.6.)

For now it's enough to confirm the route is registered: curl `-i` against an unknown session ID:

```bash
curl -i http://127.0.0.1:47291/sessions/nope/refinement
```

Expected: `HTTP/1.1 404 Not Found` with `{"error":"unknown session"}`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "workspace: GET /sessions/{id}/refinement with timeout + 404 paths"
```

### Task 3.4: PlanWebView — line numbering + selection bridge

**Files:**
- Modify: `Sources/NudgeAIWorkspace/Resources/plan-renderer.js`
- Create: `Sources/NudgeAIWorkspace/UI/Plan/PlanSelection.swift`
- Create: `Sources/NudgeAIWorkspace/UI/Plan/PlanWebView.swift`

The injected JS finds the rendered text content, identifies line boundaries (one DOM node per line is too brittle for arbitrary plan HTML — instead, we split by `\n` in the source and wrap each line in a `<span data-line=N>` before rendering), and reports selections back to Swift.

- [ ] **Step 1: Write the JS**

`Sources/NudgeAIWorkspace/Resources/plan-renderer.js`:

```javascript
// Reports {startLine, endLine, excerpt} to Swift whenever the user
// selects text inside the rendered plan body. Line numbering is keyed off
// data-line attributes that Swift injects into the HTML before loading.

(function () {
    function emit() {
        const sel = window.getSelection();
        if (!sel || sel.isCollapsed) {
            window.webkit.messageHandlers.planSelection.postMessage({ cleared: true });
            return;
        }
        const range = sel.getRangeAt(0);
        const lines = collectLines(range);
        if (lines.length === 0) {
            window.webkit.messageHandlers.planSelection.postMessage({ cleared: true });
            return;
        }
        const startLine = Math.min(...lines.map(l => l.line));
        const endLine = Math.max(...lines.map(l => l.line));
        const excerpt = sel.toString();
        window.webkit.messageHandlers.planSelection.postMessage({
            startLine, endLine, excerpt
        });
    }

    function collectLines(range) {
        const result = [];
        const walker = document.createTreeWalker(
            range.commonAncestorContainer,
            NodeFilter.SHOW_ELEMENT,
            {
                acceptNode: (node) =>
                    node.dataset && node.dataset.line && range.intersectsNode(node)
                        ? NodeFilter.FILTER_ACCEPT
                        : NodeFilter.FILTER_SKIP
            }
        );
        let node;
        while ((node = walker.nextNode())) {
            result.push({ line: parseInt(node.dataset.line, 10) });
        }
        return result;
    }

    document.addEventListener('selectionchange', emit, { passive: true });
})();
```

- [ ] **Step 2: PlanSelection model**

`Sources/NudgeAIWorkspace/UI/Plan/PlanSelection.swift`:

```swift
import Foundation

struct PlanSelectionMessage: Codable {
    let cleared: Bool?
    let startLine: Int?
    let endLine: Int?
    let excerpt: String?

    var asSelection: PlanSelection? {
        guard cleared != true, let s = startLine, let e = endLine, let x = excerpt else { return nil }
        return PlanSelection(startLine: s, endLine: e, excerpt: x)
    }
}
```

- [ ] **Step 3: PlanWebView NSViewRepresentable**

`Sources/NudgeAIWorkspace/UI/Plan/PlanWebView.swift`:

```swift
import SwiftUI
import WebKit

struct PlanWebView: NSViewRepresentable {
    let planPath: String
    @Binding var selection: PlanSelection?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs
        let pagePrefs = WKPreferences()
        config.preferences = pagePrefs
        // Disable file access from file URLs explicitly.
        config.setValue(false, forKey: "allowFileAccessFromFileURLs")
        config.setValue(false, forKey: "allowUniversalAccessFromFileURLs")

        let userScript = WKUserScript(
            source: loadRendererJS(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(context.coordinator, name: "planSelection")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let url = URL(fileURLWithPath: planPath)
        let dir = url.deletingLastPathComponent()
        let raw = (try? String(contentsOf: url, encoding: .utf8)) ?? "<pre>plan file unreadable</pre>"
        let numbered = injectLineMarkers(into: raw)
        webView.loadHTMLString(numbered, baseURL: dir)
    }

    private func loadRendererJS() -> String {
        guard let path = Bundle.module.path(forResource: "plan-renderer", ofType: "js"),
              let body = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ""
        }
        return body
    }

    private func injectLineMarkers(into html: String) -> String {
        var out = ""
        var lineNo = 0
        for line in html.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            out += "<span data-line=\"\(lineNo)\">\(line)</span>\n"
        }
        return out
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        @Binding var selection: PlanSelection?

        init(selection: Binding<PlanSelection?>) {
            self._selection = selection
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "planSelection",
                  let body = message.body as? [String: Any] else { return }
            let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
            let parsed = try? JSONDecoder().decode(PlanSelectionMessage.self, from: data)
            DispatchQueue.main.async { [weak self] in
                self?.selection = parsed?.asSelection
            }
        }
    }
}
```

Note on `injectLineMarkers`: wrapping arbitrary HTML inside spans breaks for any content where a line crosses element boundaries (e.g. a `<div>` on line 5 with `</div>` on line 7). For V1 this is acceptable — plan HTML is LLM-authored from a template, predictably one-statement-per-line. If the LLM emits multi-line block elements, the visible HTML still renders correctly because browsers tolerate stray `<span>` tags around block content; selection just snaps to the first line of the block.

- [ ] **Step 4: Build (no test step — UI code)**

```bash
make dev
```

Expected: succeeds. (Visual verification happens in Task 3.5 where the view is wired into a tab.)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "workspace: PlanWebView with line-numbering injection + selection bridge"
```

### Task 3.5: PlanTabView with chat sidebar (visual smoke required)

**Files:**
- Create: `Sources/NudgeAIWorkspace/UI/Plan/ChatSidebar.swift`
- Create: `Sources/NudgeAIWorkspace/UI/Plan/PlanTabView.swift`
- Modify: `Sources/NudgeAIWorkspace/UI/MainWindowController.swift`

- [ ] **Step 1: ChatSidebar**

`Sources/NudgeAIWorkspace/UI/Plan/ChatSidebar.swift`:

```swift
import SwiftUI

struct ChatMessage: Identifiable {
    enum Source { case user, plan }
    let id = UUID()
    let source: Source
    let body: String
}

struct ChatSidebar: View {
    @Binding var selection: PlanSelection?
    @Binding var draft: String
    @State var messages: [ChatMessage] = []
    let onSend: (String, PlanSelection?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        Text(msg.body)
                            .padding(10)
                            .background(msg.source == .user ? Color.accentColor.opacity(0.15) : Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .frame(maxWidth: .infinity, alignment: msg.source == .user ? .trailing : .leading)
                    }
                }
                .padding(12)
            }
            Divider()
            selectionChip
            composer
        }
        .frame(minWidth: 320)
    }

    @ViewBuilder
    private var selectionChip: some View {
        if let sel = selection {
            HStack(spacing: 6) {
                Text("Lines \(sel.startLine)–\(sel.endLine)")
                    .font(.callout)
                Spacer()
                Button { selection = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            TextEditor(text: $draft)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Send") {
                    let sel = selection
                    let body = draft
                    messages.append(ChatMessage(source: .user, body: descriptionFor(sel: sel, body: body)))
                    onSend(body, sel)
                    draft = ""
                    selection = nil
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
                .disabled(draft.isEmpty && selection == nil)
            }
        }
        .padding(12)
    }

    private func descriptionFor(sel: PlanSelection?, body: String) -> String {
        if let sel { return "Lines \(sel.startLine)–\(sel.endLine): \(body)" }
        return body
    }
}
```

- [ ] **Step 2: PlanTabView**

`Sources/NudgeAIWorkspace/UI/Plan/PlanTabView.swift`:

```swift
import SwiftUI

struct PlanTabView: View {
    let session: PlanSession
    @State private var selection: PlanSelection?
    @State private var draft: String = ""

    var body: some View {
        HSplitView {
            PlanWebView(planPath: session.planPath, selection: $selection)
                .frame(minWidth: 600)

            ChatSidebar(selection: $selection, draft: $draft) { chat, sel in
                Task {
                    let payload = RefinementPayload(
                        kind: .refinement,
                        selection: sel,
                        chat: chat.isEmpty ? nil : chat,
                        planPath: session.planPath,
                        url: nil,
                        items: nil
                    )
                    await session.pending.resolve(payload)
                }
            }
        }
    }
}
```

- [ ] **Step 3: MainWindowController.openPlanTab implementation**

Replace the stub in `Sources/NudgeAIWorkspace/UI/MainWindowController.swift` with a tab-aware version. The window now uses an `NSTabViewController`:

```swift
import AppKit
import SwiftUI

final class MainWindowController: NSWindowController {
    private let tabs = NSTabViewController()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NudgeAI Workspace"
        window.center()
        self.init(window: window)

        tabs.tabStyle = .toolbar
        showEmptyState()
        window.contentViewController = tabs
    }

    private func showEmptyState() {
        guard tabs.tabViewItems.isEmpty else { return }
        let host = NSHostingController(rootView: EmptyStateView())
        let item = NSTabViewItem(viewController: host)
        item.label = "Waiting"
        tabs.addTabViewItem(item)
    }

    func openPlanTab(for session: PlanSession) {
        DispatchQueue.main.async {
            self.removeEmptyStateIfPresent()
            let host = NSHostingController(rootView: PlanTabView(session: session))
            let item = NSTabViewItem(viewController: host)
            item.label = (session.planPath as NSString).lastPathComponent
            self.tabs.addTabViewItem(item)
            self.tabs.selectedTabViewItemIndex = self.tabs.tabViewItems.count - 1
        }
    }

    private func removeEmptyStateIfPresent() {
        if let empty = tabs.tabViewItems.first, empty.label == "Waiting" {
            tabs.removeTabViewItem(empty)
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
make dev
```

- [ ] **Step 5: Visual smoke — create a sample plan file and trigger /sessions/plan**

```bash
cat > /tmp/sample-plan.html <<'EOF'
<h1>Sample plan</h1>
<p>Step 1. Do this.</p>
<p>Step 2. Then this.</p>
<p>Step 3. Verify.</p>
EOF

open NudgeAIWorkspace.app

curl -X POST http://127.0.0.1:47291/sessions/plan \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"abc","planPath":"/tmp/sample-plan.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}'
```

Expected: a new tab opens labelled `sample-plan.html`. The web view renders the HTML. Selecting text shows the selection chip in the sidebar with line numbers. Typing in the composer and clicking Send clears the composer and queues a refinement on the session (no consumer yet — verified in Task 3.6).

**This is a UI change in a webview-rendered context. Capture a screenshot** (`Cmd+Shift+5` → window) **and save to** `/tmp/plan-tab-smoke.png`. Visual sanity check: split pane is proportional, the chat sidebar's Send button uses `.borderedProminent` (matches `InstructionPanelView` pattern), no clipped text.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: PlanTabView with web view + chat sidebar

Selecting text in the web view shows a selection chip in the chat sidebar.
Send queues a RefinementPayload on the session's PendingRefinement.
EOF
)"
```

### Task 3.6: End-to-end round-trip — long-poll resolves on Send

**Files:** (validation only)

- [ ] **Step 1: Three-terminal smoke**

Terminal A (start the app):

```bash
make dev
open NudgeAIWorkspace.app
```

Terminal B (open the plan):

```bash
curl -X POST http://127.0.0.1:47291/sessions/plan \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"abc","planPath":"/tmp/sample-plan.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}'
```

Terminal C (long-poll for the refinement):

```bash
curl -N --max-time 700 http://127.0.0.1:47291/sessions/abc/refinement
```

(curl hangs)

In the Workspace UI: select "Step 2", type "drop this step" in the composer, click Send.

Expected (Terminal C):

```json
{"kind":"refinement","selection":{"startLine":3,"endLine":3,"excerpt":"Step 2. Then this."},"chat":"drop this step","planPath":"/tmp/sample-plan.html","url":null,"items":null}
```

The composer clears, the selection chip clears. The long-poll completes; curl exits.

- [ ] **Step 2: Re-poll while no message pending (verifies timeout path)**

```bash
curl -N --max-time 5 http://127.0.0.1:47291/sessions/abc/refinement
```

Expected: after ~5 seconds the **client** times out (server timeout is 600s; we abort at 5 with `--max-time`). In production the slash command will re-poll.

To verify the **server-side** timeout path, edit `main.swift` to use `.seconds(3)` for `RefinementHandler` temporarily, rebuild, re-run, observe the `{"kind":"timeout",...}` response, then restore to `.seconds(600)`. **Restore before committing.**

- [ ] **Step 3: Send-when-no-poll-active (verifies queued behavior)**

Click Send in the UI again with no curl polling. Then start a new poll:

```bash
curl -N --max-time 5 http://127.0.0.1:47291/sessions/abc/refinement
```

Expected: the queued payload returns immediately (not after 5 seconds).

- [ ] **Step 4: Commit (no source changes; this task is verification-only)**

If you needed temporary edits for the timeout smoke, confirm they're reverted:

```bash
git status
```

Expected: clean.

### Task 3.7: PlanFileWatcher — live reload on disk changes

**Files:**
- Create: `Sources/NudgeAIWorkspace/UI/Plan/PlanFileWatcher.swift`
- Modify: `Sources/NudgeAIWorkspace/UI/Plan/PlanTabView.swift`

- [ ] **Step 1: PlanFileWatcher**

`Sources/NudgeAIWorkspace/UI/Plan/PlanFileWatcher.swift`:

```swift
import Foundation

final class PlanFileWatcher {
    private let path: String
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    let onChange: () -> Void

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    func start() {
        fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.onChange()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fd >= 0 { close(self.fd) }
            self.fd = -1
        }
        src.resume()
        self.source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Wire watcher into PlanTabView**

In `Sources/NudgeAIWorkspace/UI/Plan/PlanTabView.swift`, add a `@State` `reloadTick` to force the web view to re-render and a `.onAppear` setting up the watcher:

```swift
struct PlanTabView: View {
    let session: PlanSession
    @State private var selection: PlanSelection?
    @State private var draft: String = ""
    @State private var reloadTick: Int = 0
    @State private var watcher: PlanFileWatcher?

    var body: some View {
        HSplitView {
            PlanWebView(planPath: session.planPath, selection: $selection)
                .id(reloadTick)
                .frame(minWidth: 600)

            ChatSidebar(/* ...as before... */) { chat, sel in
                /* ...as before... */
            }
        }
        .onAppear {
            let w = PlanFileWatcher(path: session.planPath) {
                reloadTick &+= 1
            }
            w.start()
            self.watcher = w
        }
        .onDisappear {
            watcher?.stop()
        }
    }
}
```

The `.id(reloadTick)` modifier forces SwiftUI to treat the PlanWebView as a fresh view each time the tick increments, triggering `updateNSView` to re-read the file.

- [ ] **Step 3: Smoke**

```bash
make dev
open NudgeAIWorkspace.app

cat > /tmp/sample-plan.html <<'EOF'
<h1>Plan</h1>
<p>Original line.</p>
EOF

curl -X POST http://127.0.0.1:47291/sessions/plan \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"abc","planPath":"/tmp/sample-plan.html","branch":"main","repoRoot":"/r","originLLM":"claude-code"}'
```

In a separate terminal:

```bash
cat > /tmp/sample-plan.html <<'EOF'
<h1>Plan</h1>
<p>Edited line.</p>
EOF
```

Expected: the Workspace tab updates within ~100 ms to show "Edited line.". No reload click required.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "workspace: PlanFileWatcher live-reloads PlanWebView on disk changes"
```

### Task 3.8: Tab close and end-session semantics

**Files:**
- Modify: `Sources/NudgeAIWorkspace/UI/MainWindowController.swift`
- Create: `Sources/NudgeAIWorkspace/Bridge/EndSessionHandler.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`

- [ ] **Step 1: EndSessionHandler**

`Sources/NudgeAIWorkspace/Bridge/EndSessionHandler.swift`:

```swift
import Foundation

struct EndSessionHandler {
    let store: SessionStore

    func handle(_ req: HTTPRequest, params: [String: String]) async -> HTTPResponse {
        guard let id = params["id"], let session = await store.session(id: id) else {
            return .error(status: 404, message: "unknown session")
        }
        await session.pending.resolve(.ended)
        await store.remove(id: id)
        return .json(status: 200, body: #"{"ok":true}"#)
    }
}
```

- [ ] **Step 2: Register the route in main.swift**

```swift
let endHandler = EndSessionHandler(store: store)
router.register(method: "POST", pattern: "/sessions/{id}/end") { req, params in
    await endHandler.handle(req, params: params)
}
```

- [ ] **Step 3: Add a close button to each tab**

Customize the `NSTabViewItem` label with a small close button using a SwiftUI overlay, or use the simpler approach: handle the tab-view's selection-changed delegate to add a contextual menu "Close Tab". For V1, a contextual menu is sufficient.

In `MainWindowController.swift`, conform to `NSTabViewControllerDelegate`-style or add:

```swift
extension MainWindowController {
    func closeTab(at index: Int) async {
        let item = tabs.tabViewItems[index]
        if let host = item.viewController as? NSHostingController<PlanTabView> {
            let session = host.rootView.session
            await session.pending.resolve(.ended)
        }
        tabs.removeTabViewItem(item)
        if tabs.tabViewItems.isEmpty { showEmptyState() }
    }
}
```

Add a menu item to the window's menu (or just a right-click context menu on tabs — keep it simple for V1).

- [ ] **Step 4: Smoke**

```bash
make dev
open NudgeAIWorkspace.app
```

POST a plan session, start a long-poll, then call:

```bash
curl -i -X POST http://127.0.0.1:47291/sessions/abc/end
```

Expected: 200; the long-poll resolves with `{"kind":"ended"}`. A subsequent poll for `abc` returns 404.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "workspace: end-session endpoint + tab close resolves pending poll with ended"
```

---

## Phase 4 — Verify flow (capture mode only)

Goal: `POST /sessions/verify` opens a verify tab that loads a URL in a webview; capture-mode overlay lets the user drag boxes + write instructions; Send returns `verify-capture` payload with screenshot paths.

### Task 4.1: VerifySession + handler

**Files:**
- Create: `Sources/NudgeAIWorkspace/Bridge/VerifySession.swift`
- Create: `Sources/NudgeAIWorkspace/Bridge/VerifyHandler.swift`
- Modify: `Sources/NudgeAIWorkspace/main.swift`
- Create: `Tests/NudgeAIWorkspaceTests/VerifyHandlerTests.swift`

- [ ] **Step 1: VerifySession**

`Sources/NudgeAIWorkspace/Bridge/VerifySession.swift`:

```swift
import Foundation

final class VerifySession: Session {
    let id: String
    let url: String
    let repoRoot: String
    let originLLM: String
    let pending = PendingRefinement()

    init(id: String, url: String, repoRoot: String, originLLM: String) {
        self.id = id
        self.url = url
        self.repoRoot = repoRoot
        self.originLLM = originLLM
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/NudgeAIWorkspaceTests/VerifyHandlerTests.swift`:

```swift
import XCTest
@testable import NudgeAIWorkspace

final class VerifyHandlerTests: XCTestCase {
    func testValidPostCreatesVerifySession() async {
        let store = SessionStore()
        let handler = VerifyHandler(store: store, openTab: { _ in })
        let body = Data(#"{"sessionId":"v1","url":"http://localhost:3000","repoRoot":"/r","originLLM":"claude-code"}"#.utf8)
        let req = HTTPRequest(method: "POST", path: "/sessions/verify", headers: CaseInsensitiveHeaders(), body: body)
        let res = await handler.handle(req, params: [:])
        XCTAssertEqual(res.status, 200)
        XCTAssertNotNil(await store.session(id: "v1") as? VerifySession)
    }
}
```

- [ ] **Step 3: Implement VerifyHandler**

`Sources/NudgeAIWorkspace/Bridge/VerifyHandler.swift`:

```swift
import Foundation

struct VerifyHandlerRequest: Codable {
    let sessionId: String
    let url: String
    let repoRoot: String
    let originLLM: String
}

struct VerifyHandler {
    let store: SessionStore
    let openTab: (VerifySession) async -> Void

    func handle(_ req: HTTPRequest, params: [String: String]) async -> HTTPResponse {
        guard let body = try? JSONDecoder().decode(VerifyHandlerRequest.self, from: req.body) else {
            return .error(status: 400, message: "invalid request body")
        }
        let session = VerifySession(
            id: body.sessionId,
            url: body.url,
            repoRoot: body.repoRoot,
            originLLM: body.originLLM
        )
        await store.upsert(session)
        if let existing = await store.session(id: body.sessionId) as? VerifySession {
            await openTab(existing)
        }
        return .json(status: 200, body: #"{"sessionId":"\#(body.sessionId)"}"#)
    }
}
```

- [ ] **Step 4: Register the route**

In `main.swift` (next to plan registration):

```swift
let openVerifyTab: (VerifySession) async -> Void = { session in
    await MainActor.run {
        delegate.windowController?.openVerifyTab(for: session)
    }
}
let verifyHandler = VerifyHandler(store: store, openTab: openVerifyTab)
router.register(method: "POST", pattern: "/sessions/verify") { req, params in
    await verifyHandler.handle(req, params: params)
}
```

- [ ] **Step 5: Stub openVerifyTab on MainWindowController**

```swift
func openVerifyTab(for session: VerifySession) {
    NSLog("openVerifyTab: \(session.id) at \(session.url)")
}
```

- [ ] **Step 6: Run test**

```bash
swift test --filter VerifyHandlerTests
```

Expected: pass.

- [ ] **Step 7: Build + smoke**

```bash
make dev
open NudgeAIWorkspace.app
curl -i -X POST http://127.0.0.1:47291/sessions/verify \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"v1","url":"https://example.com","repoRoot":"/r","originLLM":"claude-code"}'
```

Expected: 200. Console shows `openVerifyTab: v1 at https://example.com`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "workspace: POST /sessions/verify + VerifySession + handler"
```

### Task 4.2: VerifyTabView with WKWebView and mode toggle

**Files:**
- Create: `Sources/NudgeAIWorkspace/UI/Verify/VerifyWebView.swift`
- Create: `Sources/NudgeAIWorkspace/UI/Verify/TweakModeStub.swift`
- Create: `Sources/NudgeAIWorkspace/UI/Verify/VerifyTabView.swift`
- Modify: `Sources/NudgeAIWorkspace/UI/MainWindowController.swift`

- [ ] **Step 1: VerifyWebView**

`Sources/NudgeAIWorkspace/UI/Verify/VerifyWebView.swift`:

```swift
import SwiftUI
import WebKit

struct VerifyWebView: NSViewRepresentable {
    let url: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        load(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != url {
            load(into: webView)
        }
    }

    private func load(into webView: WKWebView) {
        guard let u = URL(string: url) else { return }
        webView.load(URLRequest(url: u))
    }
}
```

- [ ] **Step 2: TweakModeStub**

`Sources/NudgeAIWorkspace/UI/Verify/TweakModeStub.swift`:

```swift
import SwiftUI

struct TweakModeStub: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "paintbrush")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Tweak mode — coming soon")
                .font(.title3)
            Text("Click-to-edit CSS lands in v0.4. Use Capture mode for now.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
```

- [ ] **Step 3: VerifyTabView with mode toggle**

`Sources/NudgeAIWorkspace/UI/Verify/VerifyTabView.swift`:

```swift
import SwiftUI

enum VerifyMode: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case tweak = "Tweak"
    var id: String { rawValue }
}

struct VerifyTabView: View {
    let session: VerifySession
    @State private var mode: VerifyMode = .capture
    @State private var urlText: String

    init(session: VerifySession) {
        self.session = session
        self._urlText = State(initialValue: session.url)
    }

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            content
        }
    }

    private var urlBar: some View {
        HStack(spacing: 8) {
            TextField("URL", text: $urlText)
                .textFieldStyle(.roundedBorder)
            Picker("", selection: $mode) {
                ForEach(VerifyMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .capture:
            ZStack {
                VerifyWebView(url: urlText)
                CaptureModeOverlay(session: session)
            }
        case .tweak:
            TweakModeStub()
        }
    }
}
```

- [ ] **Step 4: Stub CaptureModeOverlay so VerifyTabView compiles**

`Sources/NudgeAIWorkspace/UI/Verify/CaptureModeOverlay.swift` (full impl in Task 4.3):

```swift
import SwiftUI

struct CaptureModeOverlay: View {
    let session: VerifySession
    var body: some View {
        Color.clear   // pass-through for now
    }
}
```

- [ ] **Step 5: Replace MainWindowController.openVerifyTab stub**

```swift
func openVerifyTab(for session: VerifySession) {
    DispatchQueue.main.async {
        self.removeEmptyStateIfPresent()
        let host = NSHostingController(rootView: VerifyTabView(session: session))
        let item = NSTabViewItem(viewController: host)
        item.label = URL(string: session.url)?.host ?? "verify"
        self.tabs.addTabViewItem(item)
        self.tabs.selectedTabViewItemIndex = self.tabs.tabViewItems.count - 1
    }
}
```

- [ ] **Step 6: Build + visual smoke**

```bash
make dev
open NudgeAIWorkspace.app
curl -X POST http://127.0.0.1:47291/sessions/verify \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"v1","url":"https://example.com","repoRoot":"/r","originLLM":"claude-code"}'
```

Expected: a new tab opens; example.com loads. Toggle between Capture and Tweak — capture shows the web view, tweak shows the "Coming soon" panel. Screenshot the result to `/tmp/verify-tab-smoke.png` for the manual smoke record.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "workspace: VerifyTabView with WKWebView + mode toggle (tweak stubbed)"
```

### Task 4.3: CaptureModeOverlay — drag boxes + per-box instruction

**Files:**
- Modify: `Sources/NudgeAIWorkspace/UI/Verify/CaptureModeOverlay.swift`
- Create: `Sources/NudgeAIWorkspace/UI/Verify/BoxedAnnotation.swift`
- Create: `Sources/NudgeAIWorkspace/Shared/InstructionPanelView.swift` (lifted from `Sources/NudgeAI/Capture/`)

Per the spec's open question about reuse strategy: for V1, **copy** `InstructionPanelView` from `Sources/NudgeAI/Capture/InstructionPanelView.swift` into `Sources/NudgeAIWorkspace/Shared/InstructionPanelView.swift` verbatim, with a `// origin: Sources/NudgeAI/Capture/InstructionPanelView.swift` comment at the top. A future refactor can extract to a shared package product; the copy is unblocked work today.

- [ ] **Step 1: Copy InstructionPanelView**

```bash
cp Sources/NudgeAI/Capture/InstructionPanelView.swift Sources/NudgeAIWorkspace/Shared/InstructionPanelView.swift
```

Edit the new file to add the origin comment at line 1:

```swift
// origin: Sources/NudgeAI/Capture/InstructionPanelView.swift
//
// V1 copies this view verbatim into the Workspace target. Future refactor:
// extract to a shared package product so the two apps share one definition.
```

- [ ] **Step 2: BoxedAnnotation**

`Sources/NudgeAIWorkspace/UI/Verify/BoxedAnnotation.swift`:

```swift
import Foundation
import CoreGraphics

struct BoxedAnnotation: Identifiable {
    let id = UUID()
    var rect: CGRect
    var instruction: String
    var screenshotPath: String?
}
```

- [ ] **Step 3: Full CaptureModeOverlay**

Replace `Sources/NudgeAIWorkspace/UI/Verify/CaptureModeOverlay.swift`:

```swift
import SwiftUI
import WebKit

struct CaptureModeOverlay: View {
    let session: VerifySession
    @State private var annotations: [BoxedAnnotation] = []
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var pendingRect: CGRect?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture)

                ForEach(annotations) { ann in
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.08))
                        .frame(width: ann.rect.width, height: ann.rect.height)
                        .position(x: ann.rect.midX, y: ann.rect.midY)
                }

                if let rect = liveRect() {
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.05))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }

                if let pending = pendingRect {
                    InstructionPanelView(initialText: "") { text, action in
                        let ann = BoxedAnnotation(rect: pending, instruction: text)
                        annotations.append(ann)
                        pendingRect = nil
                        if action == .saveAndFinish {
                            sendAll()
                        }
                    } onCancel: {
                        pendingRect = nil
                    }
                    .position(x: pending.midX + pending.width / 2 + 200, y: pending.midY)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                let rect = CGRect.rect(from: value.startLocation, to: value.location)
                if rect.width > 10 && rect.height > 10 {
                    pendingRect = rect
                }
                dragStart = nil
                dragCurrent = nil
            }
    }

    private func liveRect() -> CGRect? {
        guard let start = dragStart, let cur = dragCurrent else { return nil }
        return CGRect.rect(from: start, to: cur)
    }

    private func sendAll() {
        // Screenshot capture lands in Task 4.4. For now, send rects + instructions.
        let items = annotations.map { ann in
            VerifyItem(
                rect: [ann.rect.origin.x, ann.rect.origin.y, ann.rect.width, ann.rect.height],
                instruction: ann.instruction,
                screenshotPath: ann.screenshotPath ?? ""
            )
        }
        Task {
            let payload = RefinementPayload(
                kind: .verifyCapture,
                selection: nil,
                chat: nil,
                planPath: nil,
                url: session.url,
                items: items
            )
            await session.pending.resolve(payload)
        }
    }
}

private extension CGRect {
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }
}
```

Note: the API for `InstructionPanelView` may differ from this sketch. Read the actual signature in `Sources/NudgeAI/Capture/InstructionPanelView.swift` and adapt the call site. The intent is `initial text + onSave(text, action) + onCancel`, matching the existing menu-bar flow's keybindings (⏎ save+rearm, ⌘⏎ save+finish).

- [ ] **Step 4: Build**

```bash
make dev
```

If the build fails because `InstructionPanelView` references symbols that don't exist in the Workspace target (e.g., `Preferences` from `Settings/`), copy the minimum dependencies as well — keep the additions to a copy-only pattern, no shared code refactor in this task.

- [ ] **Step 5: Visual smoke**

```bash
open NudgeAIWorkspace.app
curl -X POST http://127.0.0.1:47291/sessions/verify \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"v1","url":"https://example.com","repoRoot":"/r","originLLM":"claude-code"}'
```

In the Workspace UI: drag a box on the example.com page. Expected: the instruction panel pops up next to the box. Type "this header is too small", press ⏎ → the panel disappears and a persistent outlined rectangle remains where you dragged.

Screenshot to `/tmp/verify-capture-smoke.png`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: CaptureModeOverlay — drag-to-box + per-box instruction panel

Reuses InstructionPanelView from the menu-bar Capture/ flow (copied
verbatim with an origin comment; shared-package refactor deferred).
EOF
)"
```

### Task 4.4: Per-box screenshots via WKWebView.takeSnapshot

**Files:**
- Modify: `Sources/NudgeAIWorkspace/UI/Verify/CaptureModeOverlay.swift`
- Modify: `Sources/NudgeAIWorkspace/UI/Verify/VerifyTabView.swift`

- [ ] **Step 1: Pass the WKWebView reference into the overlay**

In `VerifyTabView`, expose a `WKWebView` reference. Refactor to use an `@StateObject` view-model that holds the web view:

`Sources/NudgeAIWorkspace/UI/Verify/VerifyTabView.swift` (additions):

```swift
import SwiftUI
import WebKit

final class VerifyViewModel: ObservableObject {
    @Published var webView = WKWebView()
}
```

Update `VerifyTabView`:

```swift
struct VerifyTabView: View {
    let session: VerifySession
    @State private var mode: VerifyMode = .capture
    @State private var urlText: String
    @StateObject private var vm = VerifyViewModel()
    // ...

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .capture:
            ZStack {
                VerifyWebView(url: urlText, webView: vm.webView)
                CaptureModeOverlay(session: session, webView: vm.webView)
            }
        case .tweak:
            TweakModeStub()
        }
    }
}
```

And update `VerifyWebView`:

```swift
struct VerifyWebView: NSViewRepresentable {
    let url: String
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        load(into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != url { load(into: webView) }
    }

    private func load(into webView: WKWebView) {
        guard let u = URL(string: url) else { return }
        webView.load(URLRequest(url: u))
    }
}
```

- [ ] **Step 2: Screenshot capture in sendAll()**

In `CaptureModeOverlay`, replace the no-op screenshot loop with a real `WKWebView.takeSnapshot` per annotation:

```swift
struct CaptureModeOverlay: View {
    let session: VerifySession
    let webView: WKWebView
    @State private var annotations: [BoxedAnnotation] = []
    // ... same state as before

    private func sendAll() {
        Task {
            var items: [VerifyItem] = []
            for ann in annotations {
                let path = await captureScreenshot(rect: ann.rect)
                items.append(VerifyItem(
                    rect: [ann.rect.origin.x, ann.rect.origin.y, ann.rect.width, ann.rect.height],
                    instruction: ann.instruction,
                    screenshotPath: path ?? ""
                ))
            }
            let payload = RefinementPayload(
                kind: .verifyCapture, selection: nil, chat: nil,
                planPath: nil, url: session.url, items: items
            )
            await session.pending.resolve(payload)
        }
    }

    private func captureScreenshot(rect: CGRect) async -> String? {
        let config = WKSnapshotConfiguration()
        config.rect = rect
        do {
            let image = try await webView.takeSnapshot(configuration: config)
            return writePNG(image, sessionId: session.id, index: annotations.firstIndex(where: { $0.rect == rect }) ?? 0)
        } catch {
            NSLog("snapshot failed: \(error)")
            return nil
        }
    }

    private func writePNG(_ image: NSImage, sessionId: String, index: Int) -> String? {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.nudgeai.workspace")
            .appendingPathComponent("verify")
            .appendingPathComponent(sessionId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(String(format: "%02d.png", index + 1)).path
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: URL(fileURLWithPath: path))
        return path
    }
}
```

- [ ] **Step 3: Build**

```bash
make dev
```

- [ ] **Step 4: End-to-end smoke**

Terminal A (long-poll):

```bash
curl -N --max-time 700 http://127.0.0.1:47291/sessions/v1/refinement
```

Terminal B:

```bash
open NudgeAIWorkspace.app
curl -X POST http://127.0.0.1:47291/sessions/verify \
  -H 'Content-Type: application/json' \
  -d '{"sessionId":"v1","url":"https://example.com","repoRoot":"/r","originLLM":"claude-code"}'
```

In the UI: drag a box, type "shrink this", press ⌘⏎ (save and finish).

Expected: Terminal A returns a JSON payload with `kind: "verify-capture"`, `url: "https://example.com"`, and `items[0].screenshotPath` pointing to `~/Library/Caches/com.nudgeai.workspace/verify/v1/01.png`. Open that path and verify the image is the captured region:

```bash
open ~/Library/Caches/com.nudgeai.workspace/verify/v1/01.png
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: per-box screenshots via WKWebView.takeSnapshot

Each capture-mode annotation writes a PNG to
~/Library/Caches/com.nudgeai.workspace/verify/<sessionId>/NN.png and the
absolute path ships in the verify-capture payload.
EOF
)"
```

---

## Phase 5 — Slash-command surfaces

Goal: ship two Claude Code skill files and the `nudgeai` shell binary. First-launch installer offers to register both.

### Task 5.1: Generic `nudgeai` shell binary as a separate target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/NudgeAICLI/main.swift`
- Modify: `Makefile` (to copy the binary into the Workspace .app bundle)

- [ ] **Step 1: Add the CLI executable target**

In `Package.swift`, add inside `targets`:

```swift
.executableTarget(
    name: "NudgeAICLI",
    path: "Sources/NudgeAICLI"
),
```

- [ ] **Step 2: Implement the CLI**

`Sources/NudgeAICLI/main.swift`:

```swift
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: nudgeai plan [path]   |   nudgeai verify <url>")
    exit(2)
}

let cmd = args[1]
let bridgeBase = "http://127.0.0.1:47291"

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(1)
}

func curlOrDie(_ url: String, method: String = "GET", body: String? = nil) -> Data {
    var req = URLRequest(url: URL(string: url)!)
    req.httpMethod = method
    if let body {
        req.httpBody = Data(body.utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let sem = DispatchSemaphore(value: 0)
    var data: Data?
    var error: Error?
    let task = URLSession.shared.dataTask(with: req) { d, _, e in
        data = d; error = e; sem.signal()
    }
    task.resume()
    sem.wait()
    if let error { die("network error: \(error)") }
    return data ?? Data()
}

func health() {
    let res = curlOrDie("\(bridgeBase)/health")
    if res.isEmpty {
        die("NudgeAI Workspace.app isn't running. Run: open -a \"NudgeAI Workspace\"")
    }
}

func sha1Prefix(_ s: String) -> String {
    // CryptoKit pulled in via SwiftCrypto on Linux; on macOS it's a system module.
    import Foundation
    // (real implementation uses Insecure.SHA1 via CryptoKit)
    return ""  // see step 3 — proper implementation below
}
```

Replace the broken `sha1Prefix` stub:

```swift
import CryptoKit

func sha1Prefix12(_ s: String) -> String {
    let digest = Insecure.SHA1.hash(data: Data(s.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
}

func currentBranch() -> String {
    let pipe = Pipe()
    let proc = Process()
    proc.launchPath = "/usr/bin/git"
    proc.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
    proc.standardOutput = pipe
    proc.standardError = Pipe()
    do { try proc.run() } catch { return "main" }
    proc.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "main"
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
}

switch cmd {
case "plan":
    health()
    let repoRoot = FileManager.default.currentDirectoryPath
    let branch = currentBranch()
    let providedPath = args.count >= 3 ? args[2] : nil
    let planPath = providedPath
        ?? "\(repoRoot)/docs/superpowers/plans/\(branch).html"
    let sessionId = sha1Prefix12("\(repoRoot):\(branch):\(planPath)")

    let body = #"""
    {"sessionId":"\#(sessionId)","planPath":"\#(planPath)","branch":"\#(branch)","repoRoot":"\#(repoRoot)","originLLM":"shell"}
    """#
    _ = curlOrDie("\(bridgeBase)/sessions/plan", method: "POST", body: body)

    let res = curlOrDie("\(bridgeBase)/sessions/\(sessionId)/refinement")
    FileHandle.standardOutput.write(res)

case "verify":
    guard args.count >= 3 else { die("nudgeai verify <url>") }
    let url = args[2]
    health()
    let repoRoot = FileManager.default.currentDirectoryPath
    let sessionId = sha1Prefix12("\(repoRoot)::\(url)")
    let body = #"""
    {"sessionId":"\#(sessionId)","url":"\#(url)","repoRoot":"\#(repoRoot)","originLLM":"shell"}
    """#
    _ = curlOrDie("\(bridgeBase)/sessions/verify", method: "POST", body: body)
    let res = curlOrDie("\(bridgeBase)/sessions/\(sessionId)/refinement")
    FileHandle.standardOutput.write(res)

default:
    die("unknown command: \(cmd)")
}
```

(Clean up the duplicated `import Foundation` placeholder section from step 2; the actual file is one continuous Swift program with `import Foundation` + `import CryptoKit` at the top.)

- [ ] **Step 3: Update Makefile to copy `nudgeai` binary into the bundle**

In `Makefile`, after building targets, copy `.build/.../nudgeai` to `NudgeAIWorkspace.app/Contents/MacOS/nudgeai`.

- [ ] **Step 4: Build**

```bash
make dev
ls NudgeAIWorkspace.app/Contents/MacOS/
```

Expected: both `NudgeAIWorkspace` and `nudgeai` present.

- [ ] **Step 5: Smoke**

```bash
open NudgeAIWorkspace.app

cat > /tmp/test-plan.html <<'EOF'
<h1>Test</h1><p>Hello.</p>
EOF

./NudgeAIWorkspace.app/Contents/MacOS/nudgeai plan /tmp/test-plan.html &
NUDGEAI_PID=$!
```

In the UI: type "expand" in the chat, click Send. Expected: the background `nudgeai` exits and prints the JSON payload to stdout.

```bash
wait $NUDGEAI_PID
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
workspace: nudgeai shell binary as separate executable target

NudgeAICLI talks to the bridge with URLSession + Foundation only.
nudgeai plan/verify mirror the slash commands for non-Claude-Code terminals.
EOF
)"
```

### Task 5.2: Claude Code skill files

**Files:**
- Create: `Sources/NudgeAIWorkspace/Skills/plugin.json`
- Create: `Sources/NudgeAIWorkspace/Skills/skills/nudgeai-plan/SKILL.md`
- Create: `Sources/NudgeAIWorkspace/Skills/skills/nudgeai-verify/SKILL.md`

- [ ] **Step 1: plugin.json**

`Sources/NudgeAIWorkspace/Skills/plugin.json`:

```json
{
  "name": "nudgeai",
  "version": "0.3.0",
  "description": "Slash commands for the NudgeAI Workspace dock app: /nudgeai-plan and /nudgeai-verify."
}
```

- [ ] **Step 2: nudgeai-plan skill**

`Sources/NudgeAIWorkspace/Skills/skills/nudgeai-plan/SKILL.md`:

````markdown
---
name: nudgeai-plan
description: Open the current branch's HTML plan in NudgeAI Workspace for line-by-line refinement. Returns the user's refinement as your next input.
---

# nudgeai-plan

You are invoking the NudgeAI Workspace bridge. Follow this exactly.

1. **Resolve plan path** (in order of precedence):
   - If the user passed an argument (e.g. `/nudgeai-plan docs/plans/foo.html`), use that path.
   - Else, compute `branch=$(git rev-parse --abbrev-ref HEAD)` and check `docs/superpowers/plans/${branch}.html`.
   - Else, ask the user whether to generate a fresh plan now; if yes, write it to `docs/superpowers/plans/${branch}.html`, then proceed.

2. **Health check**:

```bash
curl -sf http://127.0.0.1:47291/health \
  || (echo "❌ NudgeAI Workspace.app isn't running. Run: open -a \"NudgeAI Workspace\"" && exit 1)
```

3. **Compute session ID** (deterministic from repo+branch+path):

```bash
SESSION_ID=$(printf "%s:%s:%s" "$(pwd)" "$branch" "$plan_path" | shasum | cut -c1-12)
```

4. **POST /sessions/plan**:

```bash
curl -sf -X POST http://127.0.0.1:47291/sessions/plan \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"sessionId":"%s","planPath":"%s","branch":"%s","repoRoot":"%s","originLLM":"claude-code"}' \
       "$SESSION_ID" "$plan_path" "$branch" "$(pwd)")"
```

5. **Long-poll for the refinement** (server timeout 600 s; allow client headroom):

```bash
curl -sN --max-time 700 "http://127.0.0.1:47291/sessions/${SESSION_ID}/refinement"
```

6. **Print the JSON response** as the skill's output. Claude Code will deliver it as your next input.
````

- [ ] **Step 3: nudgeai-verify skill**

`Sources/NudgeAIWorkspace/Skills/skills/nudgeai-verify/SKILL.md`:

````markdown
---
name: nudgeai-verify
description: Open a URL in NudgeAI Workspace's verify tab. Returns the user's annotation list (rect + instruction + screenshot path per box) as your next input.
---

# nudgeai-verify

1. **Require a URL argument**:

```bash
if [ -z "$1" ]; then echo "usage: /nudgeai-verify <url>"; exit 2; fi
url="$1"
```

2. **Health check**:

```bash
curl -sf http://127.0.0.1:47291/health \
  || (echo "❌ NudgeAI Workspace.app isn't running. Run: open -a \"NudgeAI Workspace\"" && exit 1)
```

3. **Compute session ID**:

```bash
SESSION_ID=$(printf "%s::%s" "$(pwd)" "$url" | shasum | cut -c1-12)
```

4. **POST /sessions/verify**:

```bash
curl -sf -X POST http://127.0.0.1:47291/sessions/verify \
  -H 'Content-Type: application/json' \
  -d "$(printf '{"sessionId":"%s","url":"%s","repoRoot":"%s","originLLM":"claude-code"}' \
       "$SESSION_ID" "$url" "$(pwd)")"
```

5. **Long-poll for the annotation list**:

```bash
curl -sN --max-time 700 "http://127.0.0.1:47291/sessions/${SESSION_ID}/refinement"
```

6. **Print the JSON response**. Each `items[]` entry has a `screenshotPath` you can read with the Read tool.
````

- [ ] **Step 4: Smoke — install manually and invoke from Claude Code**

```bash
mkdir -p ~/.claude/plugins/nudgeai
cp -R Sources/NudgeAIWorkspace/Skills/* ~/.claude/plugins/nudgeai/
```

Then in a fresh Claude Code session, type `/nudgeai-plan /tmp/test-plan.html`. Expected: NudgeAI Workspace's tab opens, the long-poll holds, the chat round-trip works, and Claude Code sees the JSON payload as the next user turn.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "workspace: ship Claude Code skill files for /nudgeai-plan and /nudgeai-verify"
```

### Task 5.3: First-launch installer for skills + symlink

**Files:**
- Create: `Sources/NudgeAIWorkspace/UI/FirstLaunchInstaller.swift`
- Modify: `Sources/NudgeAIWorkspace/UI/AppDelegate.swift`

- [ ] **Step 1: FirstLaunchInstaller**

`Sources/NudgeAIWorkspace/UI/FirstLaunchInstaller.swift`:

```swift
import AppKit

enum FirstLaunchInstaller {
    private static let skillsInstalledKey = "ClaudeCodeSkillsInstalled"
    private static let symlinkOfferedKey = "CliSymlinkOffered"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: skillsInstalledKey) {
            offerClaudeCodeSkillInstall()
        }
        if !defaults.bool(forKey: symlinkOfferedKey) {
            offerCliSymlink()
        }
    }

    private static func offerClaudeCodeSkillInstall() {
        let alert = NSAlert()
        alert.messageText = "Install Claude Code slash commands?"
        alert.informativeText = "Adds /nudgeai-plan and /nudgeai-verify to ~/.claude/plugins/nudgeai/. You can install later from the Help menu."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Not now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        guard let source = Bundle.main.url(forResource: "Skills", withExtension: nil) else { return }
        let target = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/plugins/nudgeai")
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
        UserDefaults.standard.set(true, forKey: skillsInstalledKey)
    }

    private static func offerCliSymlink() {
        let alert = NSAlert()
        alert.messageText = "Install the nudgeai shell command?"
        alert.informativeText = "Creates a symlink at /usr/local/bin/nudgeai. Requires admin permission. You can run `ln -s` yourself instead."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Skip")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: symlinkOfferedKey)
            return
        }

        guard let binary = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("nudgeai") else { return }
        let target = "/usr/local/bin/nudgeai"
        let script = "do shell script \"ln -sf '\(binary.path)' '\(target)'\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        UserDefaults.standard.set(true, forKey: symlinkOfferedKey)
    }
}
```

- [ ] **Step 2: Bundle the Skills folder as a resource**

In `Package.swift`, change the `NudgeAIWorkspace` target's resources to include the Skills tree:

```swift
.executableTarget(
    name: "NudgeAIWorkspace",
    path: "Sources/NudgeAIWorkspace",
    exclude: ["Info.plist"],
    resources: [
        .copy("Resources/plan-renderer.js"),
        .copy("Skills")
    ]
),
```

- [ ] **Step 3: Call installer from AppDelegate**

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = MainWindowController()
    controller.showWindow(nil)
    self.windowController = controller
    FirstLaunchInstaller.runIfNeeded()
}
```

- [ ] **Step 4: Smoke**

Reset the flags then relaunch:

```bash
defaults delete com.nudgeai.workspace ClaudeCodeSkillsInstalled 2>/dev/null
defaults delete com.nudgeai.workspace CliSymlinkOffered 2>/dev/null
open NudgeAIWorkspace.app
```

Expected: two consent dialogs, in order. Accepting installs the skill files and prompts for sudo on the symlink.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "workspace: first-launch installers for Claude Code skill + nudgeai symlink"
```

---

## Phase 6 — Documentation

### Task 6.1: Update README with v0.3 sections

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add `/nudgeai-plan` and `/nudgeai-verify` sections**

Add a top-level section "Plan & Verify (v0.3)" describing:
- Two apps shipped: `NudgeAI.app` (menu-bar capture) and `NudgeAI Workspace.app` (dock).
- The bridge on `127.0.0.1:47291`.
- How to invoke the slash commands from Claude Code and the `nudgeai` CLI from any shell.
- Manual install fallback: `ln -sf "/Applications/NudgeAI Workspace.app/Contents/MacOS/nudgeai" /usr/local/bin/nudgeai`.

Keep the capture flow section as the headline — that's still the primary user surface.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — v0.3 plan/verify sections"
```

### Task 6.2: v0.3 smoke checklist

**Files:**
- Create: `docs/v0.3-smoke.md`

- [ ] **Step 1: Write the checklist**

Cover, in order:

1. `make dev` produces both `NudgeAI.app` and `NudgeAI Workspace.app`.
2. Menu-bar capture flow round-trips to clipboard (no regression from v0.2).
3. `nudgeai plan` happy path (existing file, generate-new fallback, refinement round-trip with selection, refinement round-trip without selection).
4. `nudgeai verify` capture mode (drag, instruction, screenshot lands in cache dir, JSON ships).
5. Multi-session: two terminals, two plans, two tabs. Refinements route to the correct curl process.
6. Restart Workspace mid-poll: shell retries (or fails clean if `nudgeai` is the binary).
7. Re-invoke `/nudgeai-plan` on the same plan: focuses existing tab, doesn't duplicate.
8. Port-conflict path: `nc -l 127.0.0.1 47291`, launch Workspace, see alert.
9. Send-when-no-poll: refinement queues and resolves the next poll immediately.
10. Tweak mode toggle shows "Coming soon" panel.

- [ ] **Step 2: Commit**

```bash
git add docs/v0.3-smoke.md
git commit -m "docs: v0.3 manual smoke checklist"
```

---

## Self-Review

Spec coverage:

- ✅ Two-app architecture (menu-bar unchanged) — Phase 1 + Task 2.1
- ✅ Deletion of v0.2 workspace + SwiftTerm — Phase 1
- ✅ HTTP bridge on 127.0.0.1:47291 — Phase 2
- ✅ Deterministic session IDs — Task 3.1
- ✅ Plan flow (web view + line selection + chat + payload) — Tasks 3.2–3.6
- ✅ File watcher live reload — Task 3.7
- ✅ End-session semantics — Task 3.8
- ✅ Verify flow capture mode — Phase 4
- ✅ Tweak mode stubbed — Task 4.2
- ✅ Claude Code skills + nudgeai shell — Phase 5
- ✅ First-launch installer — Task 5.3
- ✅ README + smoke checklist — Phase 6
- ✅ Codex skill deferred — explicit in spec, not a task

Risks acknowledged in plan:

- **InstructionPanelView dependency chain** flagged in Task 4.3 — engineer copies only what compiles; no shared-package refactor.
- **JS line-numbering** correctness for arbitrary HTML noted in Task 3.4 — V1 assumption is single-statement-per-line LLM output.
- **Test-target compile breakage** if NudgeAITests references deleted types — Task 1.6 step 2 catches it via `swift test`.

Placeholder scan: clean — no TBDs, no "see above", no missing code.

Type consistency: `PendingRefinement` actor consistently named across tasks; `RefinementPayload` schema fixed in Task 3.1, used identically in 3.2, 3.5, 4.3, 4.4; route patterns (`/sessions/plan`, `/sessions/verify`, `/sessions/{id}/refinement`, `/sessions/{id}/end`) match between tasks and skill files.

---

Plan complete and saved to `docs/superpowers/plans/2026-06-10-nudgeai-plan-verify-pivot.md`. Two execution options:

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
