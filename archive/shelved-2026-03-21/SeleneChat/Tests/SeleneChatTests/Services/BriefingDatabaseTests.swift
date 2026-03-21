import SeleneShared
import XCTest
@testable import SeleneChat

final class BriefingDatabaseTests: XCTestCase {

    // MARK: - groupNotesByThread Tests

    func testGroupNotesByThread() {
        let notes = [
            Note.mock(id: 1, title: "Note A"),
            Note.mock(id: 2, title: "Note B"),
            Note.mock(id: 3, title: "Note C"),
        ]

        let threadMap: [Int: (threadName: String, threadId: Int64)] = [
            1: (threadName: "Architecture", threadId: 10),
            2: (threadName: "Architecture", threadId: 10),
            3: (threadName: "Testing", threadId: 20),
        ]

        let grouped = BriefingDataService.groupNotesByThread(notes, threadMap: threadMap)

        XCTAssertEqual(grouped.count, 2, "Should have 2 thread groups")
        XCTAssertEqual(grouped["Architecture"]?.count, 2, "Architecture should have 2 notes")
        XCTAssertEqual(grouped["Testing"]?.count, 1, "Testing should have 1 note")

        // Verify thread IDs are carried through
        XCTAssertEqual(grouped["Architecture"]?.first?.threadId, 10)
        XCTAssertEqual(grouped["Testing"]?.first?.threadId, 20)
    }

    func testGroupNotesByThreadHandlesUnthreadedNotes() {
        let notes = [
            Note.mock(id: 1, title: "Threaded Note"),
            Note.mock(id: 2, title: "Unthreaded Note"),
        ]

        // Only note 1 has a thread assignment
        let threadMap: [Int: (threadName: String, threadId: Int64)] = [
            1: (threadName: "Architecture", threadId: 10),
        ]

        let grouped = BriefingDataService.groupNotesByThread(notes, threadMap: threadMap)

        // Unthreaded notes go under "Uncategorized"
        XCTAssertEqual(grouped["Architecture"]?.count, 1)
        XCTAssertEqual(grouped["Uncategorized"]?.count, 1)
        XCTAssertEqual(grouped["Uncategorized"]?.first?.note.id, 2)
    }

    func testGroupNotesByThreadEmpty() {
        let notes: [Note] = []
        let threadMap: [Int: (threadName: String, threadId: Int64)] = [:]

        let grouped = BriefingDataService.groupNotesByThread(notes, threadMap: threadMap)

        XCTAssertTrue(grouped.isEmpty, "Empty input should return empty output")
    }

    // MARK: - identifyStalledThreads Tests

    func testIdentifyStalledThreads() {
        let now = Date()
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        let threads = [
            Thread.mock(id: 1, name: "Active Thread", lastActivityAt: twoDaysAgo),
            Thread.mock(id: 2, name: "Stalled Thread", lastActivityAt: sixDaysAgo),
        ]

        let stalled = BriefingDataService.identifyStalledThreads(threads, staleDays: 5)

        XCTAssertEqual(stalled.count, 1, "Should identify 1 stalled thread")
        XCTAssertEqual(stalled.first?.name, "Stalled Thread")
    }

    func testIdentifyStalledThreadsAllActive() {
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!

        let threads = [
            Thread.mock(id: 1, name: "Thread A", lastActivityAt: oneDayAgo),
            Thread.mock(id: 2, name: "Thread B", lastActivityAt: twoDaysAgo),
        ]

        let stalled = BriefingDataService.identifyStalledThreads(threads, staleDays: 5)

        XCTAssertTrue(stalled.isEmpty, "No stalled threads should return empty array")
    }

    func testIdentifyStalledThreadsNilActivityIsTreatedAsStalled() {
        let threads = [
            Thread.mock(id: 1, name: "No Activity Thread", lastActivityAt: nil),
        ]

        let stalled = BriefingDataService.identifyStalledThreads(threads, staleDays: 5)

        XCTAssertEqual(stalled.count, 1, "Thread with nil lastActivityAt should be considered stalled")
        XCTAssertEqual(stalled.first?.name, "No Activity Thread")
    }

    // MARK: - filterCrossThreadPairs Tests

    func testCrossThreadAssociationFiltering() {
        let pairs: [(noteAId: Int, noteBId: Int, similarity: Double)] = [
            (noteAId: 1, noteBId: 2, similarity: 0.9),  // cross-thread (thread 10 vs 20)
            (noteAId: 3, noteBId: 4, similarity: 0.8),  // same thread (both thread 10)
            (noteAId: 5, noteBId: 6, similarity: 0.7),  // cross-thread (thread 10 vs 30)
        ]

        let noteThreadMap: [Int: Int64] = [
            1: 10,
            2: 20,
            3: 10,
            4: 10,
            5: 10,
            6: 30,
        ]

        let filtered = BriefingDataService.filterCrossThreadPairs(pairs, noteThreadMap: noteThreadMap)

        XCTAssertEqual(filtered.count, 2, "Should keep only cross-thread pairs")
        XCTAssertEqual(filtered[0].noteAId, 1)
        XCTAssertEqual(filtered[1].noteAId, 5)
    }

    func testFilterCrossThreadPairsExcludesUnmappedNotes() {
        let pairs: [(noteAId: Int, noteBId: Int, similarity: Double)] = [
            (noteAId: 1, noteBId: 2, similarity: 0.9),
            (noteAId: 3, noteBId: 4, similarity: 0.8),  // note 4 not in map
        ]

        let noteThreadMap: [Int: Int64] = [
            1: 10,
            2: 20,
            3: 10,
        ]

        let filtered = BriefingDataService.filterCrossThreadPairs(pairs, noteThreadMap: noteThreadMap)

        XCTAssertEqual(filtered.count, 1, "Should exclude pairs where a note has no thread mapping")
        XCTAssertEqual(filtered[0].noteAId, 1)
    }
}
