import SeleneShared
import Foundation
import SQLite

class TodayService {
    private let db: Connection

    // Tables
    private let rawNotes = Table("raw_notes")
    private let threadsTable = Table("threads")
    private let threadNotesTable = Table("thread_notes")

    // raw_notes columns
    private let noteId = Expression<Int64>("id")
    private let noteTitle = Expression<String>("title")
    private let noteContent = Expression<String>("content")
    private let noteCreatedAt = Expression<String>("created_at")
    private let noteTestRun = Expression<String?>("test_run")

    // threads columns
    private let threadId = Expression<Int64>("id")
    private let threadName = Expression<String>("name")
    private let threadSummary = Expression<String?>("summary")
    private let threadStatus = Expression<String>("status")
    private let threadNoteCount = Expression<Int64>("note_count")
    private let threadMomentumScore = Expression<Double?>("momentum_score")

    // thread_notes columns
    private let tnThreadId = Expression<Int64>("thread_id")
    private let tnRawNoteId = Expression<Int64>("raw_note_id")

    /// ISO8601 formatter with fractional seconds support for parsing database timestamps
    private lazy var iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Parse date string from SQLite format or ISO8601
    private func parseDateString(_ dateString: String) -> Date? {
        // Try SQLite format first: "YYYY-MM-DD HH:MM:SS"
        let sqliteFormatter = DateFormatter()
        sqliteFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sqliteFormatter.timeZone = TimeZone(identifier: "UTC")

        if let date = sqliteFormatter.date(from: dateString) {
            return date
        }

        // Fall back to ISO8601 (with fractional seconds support)
        return iso8601Formatter.date(from: dateString)
    }

    init(db: Connection) {
        self.db = db
    }

    /// Get notes created after cutoff date, with thread info if connected
    func getNewCaptures(since cutoff: Date, limit: Int = 10) throws -> [NoteWithThread] {
        #if DEBUG
        DebugLogger.shared.log(.state, "TodayService: fetching new captures since \(cutoff)")
        #endif

        let cutoffString = iso8601Formatter.string(from: cutoff)

        // Query notes with optional thread join
        let query = rawNotes
            .join(.leftOuter, threadNotesTable, on: rawNotes[noteId] == threadNotesTable[tnRawNoteId])
            .join(.leftOuter, threadsTable, on: threadNotesTable[tnThreadId] == threadsTable[threadId])
            .filter(rawNotes[noteCreatedAt] > cutoffString)
            .filter(rawNotes[noteTestRun] == nil)
            .order(rawNotes[noteCreatedAt].desc)
            .limit(limit)

        var results: [NoteWithThread] = []

        for row in try db.prepare(query) {
            let createdAtString = row[rawNotes[noteCreatedAt]]
            let createdAt = parseDateString(createdAtString) ?? Date()
            let content = row[rawNotes[noteContent]]
            let preview = String(content.prefix(80))

            // Safely access optional joined columns using try?
            let joinedThreadId: Int64? = try? row.get(threadsTable[threadId])
            let joinedThreadName: String? = try? row.get(threadsTable[threadName])

            let note = NoteWithThread(
                id: row[rawNotes[noteId]],
                title: row[rawNotes[noteTitle]],
                preview: preview,
                createdAt: createdAt,
                threadName: joinedThreadName,
                threadId: joinedThreadId
            )
            results.append(note)
        }

        return results
    }

    /// Get threads with momentum, sorted by score descending
    func getHeatingUpThreads(limit: Int = 5) throws -> [ThreadSummary] {
        #if DEBUG
        DebugLogger.shared.log(.state, "TodayService: fetching heating up threads (limit: \(limit))")
        #endif

        let query = threadsTable
            .filter(threadStatus == "active")
            .filter(threadMomentumScore > 0)
            .order(threadMomentumScore.desc)
            .limit(limit)

        var results: [ThreadSummary] = []

        for row in try db.prepare(query) {
            let id = row[threadId]
            let recentTitles = try getRecentNoteTitles(forThread: id, limit: 3)

            let thread = ThreadSummary(
                id: id,
                name: row[threadName],
                summary: row[threadSummary] ?? "",
                noteCount: Int(row[threadNoteCount]),
                momentumScore: row[threadMomentumScore] ?? 0,
                recentNoteTitles: recentTitles
            )
            results.append(thread)
        }

        return results
    }

    /// Get recent note titles for a thread
    private func getRecentNoteTitles(forThread threadId: Int64, limit: Int = 3) throws -> [String] {
        let query = rawNotes
            .select(rawNotes[noteTitle])
            .join(threadNotesTable, on: rawNotes[noteId] == threadNotesTable[tnRawNoteId])
            .filter(threadNotesTable[tnThreadId] == threadId)
            .order(rawNotes[noteCreatedAt].desc)
            .limit(limit)

        var titles: [String] = []
        for row in try db.prepare(query) {
            titles.append(row[rawNotes[noteTitle]])
        }
        return titles
    }
}
