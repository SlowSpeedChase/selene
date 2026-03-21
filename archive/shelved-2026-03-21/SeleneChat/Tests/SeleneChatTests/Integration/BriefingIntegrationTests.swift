import SeleneShared
import XCTest
@testable import SeleneChat

final class BriefingIntegrationTests: XCTestCase {

    // MARK: - Test 1: Data Service Groups Notes By Thread

    func testDataServiceGroupsNotesByThread() {
        let notes = [
            Note.mock(id: 1, title: "Note A"),
            Note.mock(id: 2, title: "Note B"),
            Note.mock(id: 3, title: "Unthreaded Note")
        ]

        let threadMap: [Int: (threadName: String, threadId: Int64)] = [
            1: ("Focus Systems", 5),
            2: ("Focus Systems", 5)
        ]

        let grouped = BriefingDataService.groupNotesByThread(notes, threadMap: threadMap)

        XCTAssertEqual(grouped["Focus Systems"]?.count, 2, "Two notes should be in Focus Systems")
        XCTAssertEqual(grouped["Uncategorized"]?.count, 1, "One note should be uncategorized")
    }

    // MARK: - Test 2: Data Service Identifies Stalled Threads

    func testDataServiceIdentifiesStalledThreads() {
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!

        let threads = [
            Thread.mock(id: 1, name: "Active Thread", lastActivityAt: twoDaysAgo),
            Thread.mock(id: 2, name: "Stalled Thread", lastActivityAt: sixDaysAgo),
            Thread.mock(id: 3, name: "Very Stalled", lastActivityAt: nil)
        ]

        let stalled = BriefingDataService.identifyStalledThreads(threads, staleDays: 5)

        XCTAssertEqual(stalled.count, 2, "Should find 2 stalled threads")
        XCTAssertTrue(stalled.contains { $0.name == "Stalled Thread" })
        XCTAssertTrue(stalled.contains { $0.name == "Very Stalled" })
        XCTAssertFalse(stalled.contains { $0.name == "Active Thread" })
    }

    // MARK: - Test 3: Briefing State Flow from Load to Display

    func testBriefingStateFlowFromLoadToDisplay() {
        var state = BriefingState()
        XCTAssertEqual(state.status, .notLoaded, "Initial status should be .notLoaded")

        state.status = .loading
        XCTAssertEqual(state.status, .loading, "Status should transition to .loading")

        let briefing = StructuredBriefing(
            intro: "Good morning!",
            whatChanged: [BriefingCard.whatChanged(
                noteTitle: "Test Note",
                noteId: 1,
                threadName: "Thread",
                threadId: 5,
                date: Date(),
                primaryTheme: "focus",
                energyLevel: "high"
            )],
            needsAttention: [],
            connections: [],
            generatedAt: Date()
        )
        state.status = .loaded(briefing)

        if case .loaded(let loadedBriefing) = state.status {
            XCTAssertEqual(loadedBriefing.whatChanged.count, 1, "Should have 1 what-changed card")
            XCTAssertFalse(loadedBriefing.isEmpty, "Briefing should not be empty")
        } else {
            XCTFail("Status should be .loaded")
        }
    }

    // MARK: - Test 4: Briefing State Flow with Error

    func testBriefingStateFlowWithError() {
        var state = BriefingState()
        state.status = .loading
        XCTAssertEqual(state.status, .loading)

        let errorMessage = "Failed to connect to Ollama: Connection refused"
        state.status = .failed(errorMessage)

        if case .failed(let message) = state.status {
            XCTAssertEqual(message, errorMessage)
            XCTAssertTrue(message.contains("Ollama"))
        } else {
            XCTFail("Status should be .failed")
        }
    }

    // MARK: - Test 5: Card Factory Methods Produce Correct Types

    func testCardFactoryMethods() {
        let whatChanged = BriefingCard.whatChanged(
            noteTitle: "Test", noteId: 1, threadName: "Thread", threadId: 5,
            date: Date(), primaryTheme: "focus", energyLevel: "high"
        )
        XCTAssertEqual(whatChanged.cardType, .whatChanged)
        XCTAssertEqual(whatChanged.noteTitle, "Test")
        XCTAssertEqual(whatChanged.energyEmoji, "\u{26A1}")

        let needsAttention = BriefingCard.needsAttention(
            threadName: "Stalled", threadId: 3, reason: "no activity", noteCount: 5, openTaskCount: 2
        )
        XCTAssertEqual(needsAttention.cardType, .needsAttention)
        XCTAssertEqual(needsAttention.openTaskCount, 2)

        let connection = BriefingCard.connection(
            noteATitle: "A", noteAId: 1, threadAName: "T1",
            noteBTitle: "B", noteBId: 2, threadBName: "T2",
            explanation: "Related"
        )
        XCTAssertEqual(connection.cardType, .connection)
        XCTAssertEqual(connection.explanation, "Related")
    }

    // MARK: - Test 6: Structured Briefing isEmpty

    func testStructuredBriefingIsEmpty() {
        let empty = StructuredBriefing(
            intro: "Nothing new", whatChanged: [], needsAttention: [], connections: [], generatedAt: Date()
        )
        XCTAssertTrue(empty.isEmpty, "Empty briefing should report isEmpty")

        let nonEmpty = StructuredBriefing(
            intro: "Good morning!",
            whatChanged: [BriefingCard.whatChanged(
                noteTitle: "X", noteId: 1, threadName: nil, threadId: nil,
                date: Date(), primaryTheme: nil, energyLevel: nil
            )],
            needsAttention: [],
            connections: [],
            generatedAt: Date()
        )
        XCTAssertFalse(nonEmpty.isEmpty, "Non-empty briefing should not be empty")
    }

    // MARK: - Test 7: Context Builder End-to-End

    func testContextBuilderEndToEnd() {
        let builder = BriefingContextBuilder()

        let note = Note.mock(id: 1, title: "Deep Work", content: "Planning morning blocks for focused work")
        let thread = Thread.mock(id: 5, name: "Focus Systems", why: "Need better focus", summary: "Strategies for sustained attention")
        let related = [Note.mock(id: 2, title: "Pomodoro Notes", content: "25 min blocks work well")]
        let tasks = [ThreadTask.mock(id: 1, threadId: 5, title: "Try morning block schedule")]

        let context = builder.buildWhatChangedContext(
            note: note, thread: thread, relatedNotes: related, tasks: tasks, memories: []
        )

        XCTAssertTrue(context.contains("Deep Work"))
        XCTAssertTrue(context.contains("Planning morning blocks"))
        XCTAssertTrue(context.contains("Focus Systems"))
        XCTAssertTrue(context.contains("Strategies for sustained attention"))
        XCTAssertTrue(context.contains("Pomodoro Notes"))
        XCTAssertTrue(context.contains("Try morning block schedule"))

        let prompt = builder.buildSystemPrompt(for: .whatChanged)
        XCTAssertTrue(prompt.contains("Selene"))
        XCTAssertTrue(prompt.contains("Don't summarize"))
    }

    // MARK: - Test 8: BriefingStatus Equality

    func testBriefingStatusEquality() {
        let briefing1 = StructuredBriefing(
            intro: "Test", whatChanged: [], needsAttention: [], connections: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let briefing2 = StructuredBriefing(
            intro: "Test", whatChanged: [], needsAttention: [], connections: [],
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(BriefingStatus.notLoaded, BriefingStatus.notLoaded)
        XCTAssertEqual(BriefingStatus.loading, BriefingStatus.loading)
        XCTAssertEqual(BriefingStatus.loaded(briefing1), BriefingStatus.loaded(briefing2))
        XCTAssertEqual(BriefingStatus.failed("error"), BriefingStatus.failed("error"))

        XCTAssertNotEqual(BriefingStatus.notLoaded, BriefingStatus.loading)
        XCTAssertNotEqual(BriefingStatus.failed("error1"), BriefingStatus.failed("error2"))
    }

    // MARK: - Test 9: Cross-Thread Pair Filtering

    func testCrossThreadPairFiltering() {
        let pairs: [(noteAId: Int, noteBId: Int, similarity: Double)] = [
            (1, 2, 0.85),
            (3, 4, 0.75),
            (5, 6, 0.90),
        ]

        let noteThreadMap: [Int: Int64] = [
            1: 10, 2: 20,
            3: 10, 4: 10,
            5: 20, 6: 30,
        ]

        let filtered = BriefingDataService.filterCrossThreadPairs(pairs, noteThreadMap: noteThreadMap)

        XCTAssertEqual(filtered.count, 2, "Should filter out same-thread pair")
        XCTAssertEqual(filtered[0].noteAId, 1)
        XCTAssertEqual(filtered[1].noteAId, 5)
    }
}
