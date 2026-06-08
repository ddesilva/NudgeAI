import Foundation

/// Reads/writes `~/.config/nudgeai/agents.json`. `directory` is overridable for tests.
struct AgentConfigStore {
    static let `default`: AgentConfigStore = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".config/nudgeai", isDirectory: true)
        return AgentConfigStore(directory: dir)
    }()

    let directory: URL

    var fileURL: URL { directory.appendingPathComponent("agents.json") }

    func load() -> AgentConfigFile {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(AgentConfigFile.self, from: data)
        else { return AgentConfigFile() }
        return cfg
    }

    func save(_ cfg: AgentConfigFile) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(cfg)
        try data.write(to: fileURL, options: [.atomic])
    }
}
