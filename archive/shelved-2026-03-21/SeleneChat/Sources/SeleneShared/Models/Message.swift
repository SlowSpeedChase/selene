import Foundation

public struct Message: Identifiable, Codable, Hashable {
    public let id: UUID
    public let role: Role
    public let content: String
    public let timestamp: Date
    public let llmTier: LLMTier
    public let relatedNotes: [Int]? // Note IDs

    // Citation support
    public var citedNotes: [Note]? // Notes that were cited in the response
    public var contextNotes: [Note]? // All notes used to build context
    public var queryType: String? // For debugging/analytics
    public var voiceOriginated: Bool

    public enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    public enum LLMTier: String, Codable {
        case onDevice = "On-Device (Apple Intelligence)"
        case privateCloud = "Private Cloud (Apple)"
        case external = "External (Claude)"
        case local = "Local (Ollama)"

        public var icon: String {
            switch self {
            case .onDevice: return "\u{1F512}"
            case .privateCloud: return "\u{1F510}"
            case .external: return "\u{1F310}"
            case .local: return "\u{1F4BB}"
            }
        }

        public var color: String {
            switch self {
            case .onDevice: return "green"
            case .privateCloud: return "blue"
            case .external: return "orange"
            case .local: return "purple"
            }
        }
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        llmTier: LLMTier,
        relatedNotes: [Int]? = nil,
        citedNotes: [Note]? = nil,
        contextNotes: [Note]? = nil,
        queryType: String? = nil,
        voiceOriginated: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.llmTier = llmTier
        self.relatedNotes = relatedNotes
        self.citedNotes = citedNotes
        self.contextNotes = contextNotes
        self.queryType = queryType
        self.voiceOriginated = voiceOriginated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        llmTier = try container.decode(LLMTier.self, forKey: .llmTier)
        relatedNotes = try container.decodeIfPresent([Int].self, forKey: .relatedNotes)
        queryType = try container.decodeIfPresent(String.self, forKey: .queryType)
        voiceOriginated = try container.decodeIfPresent(Bool.self, forKey: .voiceOriginated) ?? false
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    public var isUser: Bool {
        role == .user
    }

    // Custom coding keys to exclude non-codable properties
    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, llmTier, relatedNotes, queryType, voiceOriginated
    }
}
