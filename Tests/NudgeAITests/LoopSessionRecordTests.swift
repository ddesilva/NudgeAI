import XCTest
@testable import NudgeAI

final class LoopSessionRecordTests: XCTestCase {
    func test_decodes_v1_schema() throws {
        let json = """
        {
          "format_version": 1,
          "id": "loop-20260608-onboarding-empty",
          "name": "fix-onboarding-empty-state",
          "cwd": "/Users/d/code/acme-web",
          "agent": {"key": "claude-code", "binary": "/opt/homebrew/bin/claude"},
          "created_at": "2026-06-08T10:30:00Z",
          "last_active_at": "2026-06-08T11:42:08Z",
          "status": "open",
          "preview_url": "http://localhost:3000/onboarding"
        }
        """.data(using: .utf8)!
        let rec = try JSONDecoder.loopSessionDecoder.decode(LoopSessionRecord.self, from: json)
        XCTAssertEqual(rec.id, "loop-20260608-onboarding-empty")
        XCTAssertEqual(rec.status, .open)
        XCTAssertEqual(rec.agent.key, "claude-code")
        XCTAssertEqual(rec.previewURL, URL(string: "http://localhost:3000/onboarding"))
    }

    func test_round_trips_through_json() throws {
        let original = LoopSessionRecord.fixture()
        let data = try JSONEncoder.loopSessionEncoder.encode(original)
        let decoded = try JSONDecoder.loopSessionDecoder.decode(LoopSessionRecord.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_close_marks_status_and_bumps_last_active() {
        var rec = LoopSessionRecord.fixture()
        let originalActive = rec.lastActiveAt
        rec.close(at: originalActive.addingTimeInterval(60))
        XCTAssertEqual(rec.status, .closed)
        XCTAssertEqual(rec.lastActiveAt.timeIntervalSince(originalActive), 60, accuracy: 0.01)
    }
}

private extension LoopSessionRecord {
    static func fixture() -> LoopSessionRecord {
        LoopSessionRecord(
            id: "loop-20260608-fix",
            name: "fix-something",
            cwd: "/Users/d/code/repo",
            agent: .init(key: "claude-code", binary: "/bin/claude"),
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            lastActiveAt: Date(timeIntervalSince1970: 1_780_000_500),
            status: .open,
            previewURL: nil
        )
    }
}
