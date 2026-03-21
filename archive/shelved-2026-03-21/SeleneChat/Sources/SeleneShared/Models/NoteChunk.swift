import Foundation

/// A chunk of a note representing a single idea or point.
/// Used for semantic retrieval in thread conversations.
public struct NoteChunk: Identifiable, Hashable {
    public let id: Int64
    public let noteId: Int
    public let chunkIndex: Int
    public let content: String
    public let topic: String?
    public let tokenCount: Int
    public let createdAt: Date

    public init(
        id: Int64,
        noteId: Int,
        chunkIndex: Int,
        content: String,
        topic: String?,
        tokenCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.noteId = noteId
        self.chunkIndex = chunkIndex
        self.content = content
        self.topic = topic
        self.tokenCount = tokenCount
        self.createdAt = createdAt
    }

    /// Truncated preview for display
    public var preview: String {
        if content.count <= 100 { return content }
        return String(content.prefix(100)) + "..."
    }
}

#if DEBUG
extension NoteChunk {
    public static func mock(
        id: Int64 = 1,
        noteId: Int = 1,
        chunkIndex: Int = 0,
        content: String = "This is a mock chunk about a topic.",
        topic: String? = "mock topic",
        tokenCount: Int = 8,
        createdAt: Date = Date()
    ) -> NoteChunk {
        NoteChunk(
            id: id,
            noteId: noteId,
            chunkIndex: chunkIndex,
            content: content,
            topic: topic,
            tokenCount: tokenCount,
            createdAt: createdAt
        )
    }
}
#endif
