import XCTest
@testable import NudgeAI

final class LoopSessionStoreTests: XCTestCase {
    func test_save_then_load_round_trips() throws {
        let tmp = try makeTempDir()
        let store = LoopSessionStore(root: tmp)
        let rec = LoopSessionRecord(
            id: "loop-20260608-fix",
            name: "fix",
            cwd: "/tmp/repo",
            agent: .init(key: "claude-code", binary: "/bin/claude"),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_780_000_500),
            status: .open,
            previewURL: nil
        )
        try store.save(rec)
        let loaded = try store.load(id: rec.id)
        XCTAssertEqual(loaded, rec)
    }

    func test_loadAll_returns_only_loop_folders_newest_first() throws {
        let tmp = try makeTempDir()
        let store = LoopSessionStore(root: tmp)

        let older = LoopSessionRecord(id: "loop-A", name: "a", cwd: "/x",
            agent: .init(key: "k", binary: "/b"),
            createdAt: Date(timeIntervalSince1970: 1_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_100),
            status: .open, previewURL: nil)
        let newer = LoopSessionRecord(id: "loop-B", name: "b", cwd: "/x",
            agent: .init(key: "k", binary: "/b"),
            createdAt: Date(timeIntervalSince1970: 2_000),
            lastActiveAt: Date(timeIntervalSince1970: 2_100),
            status: .open, previewURL: nil)
        try store.save(older)
        try store.save(newer)
        // Plant a non-loop folder that must be ignored.
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("Nudge-20260605"), withIntermediateDirectories: true)

        let all = store.loadAll()
        XCTAssertEqual(all.map(\.id), ["loop-B", "loop-A"])
    }

    func test_newSessionID_is_unique_and_sortable() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let id = LoopSessionStore.newSessionID(name: "Fix Onboarding Empty State!", now: now)
        XCTAssertTrue(id.hasPrefix("loop-"))
        XCTAssertTrue(id.contains("fix-onboarding-empty-state"))
        // No spaces, no unsafe chars in path components.
        XCTAssertFalse(id.contains(" "))
        XCTAssertFalse(id.contains("/"))
    }

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("nudgeai-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
