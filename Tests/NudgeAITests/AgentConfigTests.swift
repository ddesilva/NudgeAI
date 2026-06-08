import XCTest
@testable import NudgeAI

final class AgentConfigTests: XCTestCase {
    func test_decodes_minimal_config() throws {
        let json = """
        {
          "format_version": 1,
          "agents": [
            {"key": "claude-code", "display_name": "Claude Code", "binary": "/opt/homebrew/bin/claude", "args": []}
          ],
          "default_agent_key": "claude-code"
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(AgentConfigFile.self, from: json)
        XCTAssertEqual(cfg.formatVersion, 1)
        XCTAssertEqual(cfg.agents.count, 1)
        XCTAssertEqual(cfg.agents[0].key, "claude-code")
        XCTAssertEqual(cfg.defaultAgentKey, "claude-code")
    }

    func test_round_trips_through_json() throws {
        let original = AgentConfigFile(
            formatVersion: 1,
            agents: [
                AgentConfigFile.Agent(
                    key: "codex",
                    displayName: "Codex CLI",
                    binary: "/usr/local/bin/codex",
                    args: ["--model", "o4-mini"],
                    env: ["FOO": "BAR"]
                )
            ],
            defaultAgentKey: "codex"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AgentConfigFile.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_default_agent_falls_back_to_first_when_key_unknown() {
        let cfg = AgentConfigFile(
            formatVersion: 1,
            agents: [
                .init(key: "claude-code", displayName: "Claude Code", binary: "/bin/claude", args: []),
                .init(key: "codex", displayName: "Codex CLI", binary: "/bin/codex", args: []),
            ],
            defaultAgentKey: "missing"
        )
        XCTAssertEqual(cfg.resolvedDefaultAgent()?.key, "claude-code")
    }

    func test_no_agents_returns_nil_default() {
        let cfg = AgentConfigFile(formatVersion: 1, agents: [], defaultAgentKey: nil)
        XCTAssertNil(cfg.resolvedDefaultAgent())
    }
}
