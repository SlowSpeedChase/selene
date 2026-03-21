import SeleneShared
// InboxService.swift
// SeleneChat
//
// Created for Phase 7: Planning Inbox Redesign
// Manages inbox triage workflow for pending notes

import Foundation
import SQLite

class InboxService: ObservableObject {
    static let shared = InboxService()

    private var db: Connection?

    // Table references
    private let rawNotes = Table("raw_notes")
    private let processedNotes = Table("processed_notes")
    private let projects = Table("projects")

    // raw_notes columns
    private let noteId = Expression<Int64>("id")
    private let noteTitle = Expression<String>("title")
    private let noteContent = Expression<String>("content")
    private let noteCreatedAt = Expression<String>("created_at")
    private let inboxStatus = Expression<String?>("inbox_status")
    private let suggestedType = Expression<String?>("suggested_type")
    private let suggestedProjectId = Expression<Int64?>("suggested_project_id")
    private let testRun = Expression<String?>("test_run")

    // processed_notes columns
    private let rawNoteId = Expression<Int64>("raw_note_id")
    private let concepts = Expression<String?>("concepts")
    private let primaryTheme = Expression<String?>("primary_theme")
    private let energyLevel = Expression<String?>("energy_level")

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

    // projects columns
    private let projectId = Expression<Int64>("id")
    private let projectName = Expression<String>("name")

    init() {}

    func configure(with db: Connection) {
        self.db = db
    }

    // MARK: - Fetch Pending Notes

    func getPendingNotes() async throws -> [InboxNote] {
        guard let db = db else {
            throw DatabaseService.DatabaseError.notConnected
        }

        let query = rawNotes
            .join(.leftOuter, processedNotes, on: rawNotes[noteId] == processedNotes[rawNoteId])
            .join(.leftOuter, projects, on: rawNotes[suggestedProjectId] == projects[projectId])
            .filter(rawNotes[inboxStatus] == "pending" || rawNotes[inboxStatus] == nil)
            .filter(rawNotes[testRun] == nil)
            .order(rawNotes[noteCreatedAt].desc)
            .limit(50)

        var notes: [InboxNote] = []

        for row in try db.prepare(query) {
            let note = try parseInboxNote(from: row)
            notes.append(note)
        }

        return notes
    }

    private func parseInboxNote(from row: Row) throws -> InboxNote {
        // Parse concepts JSON
        var conceptsArray: [String]? = nil
        if let conceptsStr = try? row.get(processedNotes[concepts]),
           let data = conceptsStr.data(using: .utf8) {
            conceptsArray = try? JSONDecoder().decode([String].self, from: data)
        }

        // Parse suggested type
        var noteType: NoteType? = nil
        if let typeStr = try? row.get(rawNotes[suggestedType]) {
            noteType = NoteType(rawValue: typeStr)
        }

        return InboxNote(
            id: Int(try row.get(rawNotes[noteId])),
            title: try row.get(rawNotes[noteTitle]),
            content: try row.get(rawNotes[noteContent]),
            createdAt: parseDateString(try row.get(rawNotes[noteCreatedAt])) ?? Date(),
            inboxStatus: .pending,
            suggestedType: noteType,
            suggestedProjectId: (try? row.get(rawNotes[suggestedProjectId])).map { Int($0) },
            suggestedProjectName: try? row.get(projects[projectName]),
            concepts: conceptsArray,
            primaryTheme: try? row.get(processedNotes[primaryTheme]),
            energyLevel: try? row.get(processedNotes[energyLevel])
        )
    }

    // MARK: - Triage Actions

    func markTriaged(noteId: Int) async throws {
        guard let db = db else {
            throw DatabaseService.DatabaseError.notConnected
        }

        let note = rawNotes.filter(self.noteId == Int64(noteId))
        try db.run(note.update(inboxStatus <- "triaged"))
    }

    func markArchived(noteId: Int) async throws {
        guard let db = db else {
            throw DatabaseService.DatabaseError.notConnected
        }

        let note = rawNotes.filter(self.noteId == Int64(noteId))
        try db.run(note.update(inboxStatus <- "archived"))
    }

    func attachToProject(noteId: Int, projectId: Int) async throws {
        guard let db = db else {
            throw DatabaseService.DatabaseError.notConnected
        }

        // Insert into project_notes
        let projectNotes = Table("project_notes")
        let projectIdCol = Expression<Int64>("project_id")
        let rawNoteIdCol = Expression<Int64>("raw_note_id")

        try db.run(projectNotes.insert(or: .ignore,
            projectIdCol <- Int64(projectId),
            rawNoteIdCol <- Int64(noteId)
        ))

        // Mark note as triaged
        try await markTriaged(noteId: noteId)
    }
}
