import Foundation

/// A memory extracted from conversations
public struct ConversationMemory: Identifiable, Codable, Hashable {
    public let id: Int64
    public let content: String
    public let sourceSessionId: String?
    public let threadId: Int64?
    public let memoryType: MemoryType
    public var confidence: Double
    public var lastAccessed: Date?
    public let createdAt: Date
    public var updatedAt: Date

    public enum MemoryType: String, Codable, CaseIterable {
        case preference
        case fact
        case pattern
        case context
    }

    public init(
        id: Int64,
        content: String,
        sourceSessionId: String? = nil,
        threadId: Int64? = nil,
        memoryType: MemoryType,
        confidence: Double = 1.0,
        lastAccessed: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.sourceSessionId = sourceSessionId
        self.threadId = threadId
        self.memoryType = memoryType
        self.confidence = confidence
        self.lastAccessed = lastAccessed
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
