import Foundation

/// Persisted shape of `<sessionsRoot>/loop-<id>/session.json` v1.
struct LoopSessionRecord: Codable, Equatable, Identifiable {
    var formatVersion: Int
    var id: String
    var name: String
    var cwd: String
    var agent: AgentRef
    var createdAt: Date
    var lastActiveAt: Date
    var status: Status
    var previewURL: URL?

    enum Status: String, Codable, Equatable {
        case open, closed
    }

    struct AgentRef: Codable, Equatable, Hashable {
        var key: String
        var binary: String
    }

    init(
        formatVersion: Int = 1,
        id: String,
        name: String,
        cwd: String,
        agent: AgentRef,
        createdAt: Date,
        lastActiveAt: Date,
        status: Status,
        previewURL: URL?
    ) {
        self.formatVersion = formatVersion
        self.id = id
        self.name = name
        self.cwd = cwd
        self.agent = agent
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.status = status
        self.previewURL = previewURL
    }

    mutating func close(at when: Date) {
        status = .closed
        lastActiveAt = when
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case id, name, cwd, agent, status
        case createdAt = "created_at"
        case lastActiveAt = "last_active_at"
        case previewURL = "preview_url"
    }
}

extension JSONEncoder {
    /// ISO-8601 dates, sorted pretty output — used for session.json.
    static var loopSessionEncoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

extension JSONDecoder {
    static var loopSessionDecoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }
}
