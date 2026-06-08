import Foundation

/// Persisted shape of `~/.config/nudgeai/agents.json`.
struct AgentConfigFile: Codable, Equatable {
    var formatVersion: Int
    var agents: [Agent]
    var defaultAgentKey: String?

    struct Agent: Codable, Equatable, Identifiable, Hashable {
        var key: String
        var displayName: String
        var binary: String
        var args: [String]
        var env: [String: String]?

        var id: String { key }

        init(key: String, displayName: String, binary: String, args: [String] = [], env: [String: String]? = nil) {
            self.key = key
            self.displayName = displayName
            self.binary = binary
            self.args = args
            self.env = env
        }
    }

    init(formatVersion: Int = 1, agents: [Agent] = [], defaultAgentKey: String? = nil) {
        self.formatVersion = formatVersion
        self.agents = agents
        self.defaultAgentKey = defaultAgentKey
    }

    /// Returns the agent named by `defaultAgentKey`, falling back to the first
    /// configured agent. `nil` only when `agents` is empty.
    func resolvedDefaultAgent() -> Agent? {
        if let key = defaultAgentKey, let hit = agents.first(where: { $0.key == key }) {
            return hit
        }
        return agents.first
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case agents
        case defaultAgentKey = "default_agent_key"
    }
}

extension AgentConfigFile.Agent {
    enum CodingKeys: String, CodingKey {
        case key
        case displayName = "display_name"
        case binary
        case args
        case env
    }
}
