import Foundation

public struct ChatSession: Identifiable, Codable {
    public let id: UUID
    public var messages: [Message]
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String

    // Persistence tracking
    public var isPinned: Bool
    public var compressionState: CompressionState
    public var compressedAt: Date?
    public var summaryText: String?

    public init(
        id: UUID = UUID(),
        messages: [Message] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        title: String = "New Chat",
        isPinned: Bool = false,
        compressionState: CompressionState = .full,
        compressedAt: Date? = nil,
        summaryText: String? = nil
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.title = title
        self.isPinned = isPinned
        self.compressionState = compressionState
        self.compressedAt = compressedAt
        self.summaryText = summaryText
    }

    public enum CompressionState: String, Codable {
        case full          // Full messages available
        case processing    // Compression in progress
        case compressed    // Only summary available
    }

    public mutating func addMessage(_ message: Message) {
        messages.append(message)
        updatedAt = Date()

        // Auto-generate title from first user message if still "New Chat"
        if title == "New Chat", message.role == .user, !message.content.isEmpty {
            title = String(message.content.prefix(50))
        }
    }

    public var lastMessage: Message? {
        messages.last
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: updatedAt)
    }
}
