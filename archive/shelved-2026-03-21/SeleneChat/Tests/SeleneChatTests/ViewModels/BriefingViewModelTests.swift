import SeleneShared
import XCTest
@testable import SeleneChat

@MainActor
final class BriefingViewModelTests: XCTestCase {

    func testInitialState() {
        let viewModel = BriefingViewModel()
        if case .notLoaded = viewModel.state.status {
            // Expected
        } else {
            XCTFail("Expected notLoaded state")
        }
        XCTAssertFalse(viewModel.isDismissed)
    }

    func testDismiss() async {
        let viewModel = BriefingViewModel()
        await viewModel.dismiss()
        XCTAssertTrue(viewModel.isDismissed)
    }

    func testBuildWhatChangedCards() {
        let viewModel = BriefingViewModel()
        let notes = [
            Note.mock(id: 1, title: "Note A", primaryTheme: "focus", energyLevel: "high"),
            Note.mock(id: 2, title: "Note B", primaryTheme: "habits", energyLevel: "low")
        ]
        let threadMap: [Int: (threadName: String, threadId: Int64)] = [
            1: ("Focus Systems", 5),
            2: ("Daily Habits", 8)
        ]

        let cards = viewModel.buildWhatChangedCards(notes: notes, threadMap: threadMap)

        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].noteTitle, "Note A")
        XCTAssertEqual(cards[0].threadName, "Focus Systems")
        XCTAssertEqual(cards[0].energyLevel, "high")
        XCTAssertEqual(cards[1].noteTitle, "Note B")
        XCTAssertEqual(cards[1].threadName, "Daily Habits")
    }

    func testBuildWhatChangedCardsUnthreaded() {
        let viewModel = BriefingViewModel()
        let notes = [Note.mock(id: 1, title: "Loose Note")]
        let threadMap: [Int: (threadName: String, threadId: Int64)] = [:]

        let cards = viewModel.buildWhatChangedCards(notes: notes, threadMap: threadMap)

        XCTAssertEqual(cards.count, 1)
        XCTAssertNil(cards[0].threadName)
        XCTAssertNil(cards[0].threadId)
    }

    func testBuildNeedsAttentionCards() {
        let viewModel = BriefingViewModel()
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())!

        let stalledThreads = [
            Thread.mock(id: 5, name: "Stalled Thread", noteCount: 8, lastActivityAt: sixDaysAgo)
        ]
        let taskCounts: [Int64: Int] = [5: 3]

        let cards = viewModel.buildNeedsAttentionCards(threads: stalledThreads, openTaskCounts: taskCounts)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].threadName, "Stalled Thread")
        XCTAssertEqual(cards[0].openTaskCount, 3)
        XCTAssertTrue(cards[0].reason?.contains("days") == true)
        XCTAssertTrue(cards[0].reason?.contains("3 open tasks") == true)
    }

    func testBuildNeedsAttentionNoTasks() {
        let viewModel = BriefingViewModel()
        let sixDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
        let threads = [Thread.mock(id: 1, name: "Stale", lastActivityAt: sixDaysAgo)]

        let cards = viewModel.buildNeedsAttentionCards(threads: threads, openTaskCounts: [:])

        XCTAssertEqual(cards[0].openTaskCount, 0)
        XCTAssertTrue(cards[0].reason?.contains("days") == true)
        XCTAssertFalse(cards[0].reason?.contains("task") == true)
    }

    func testBuildConnectionCards() {
        let viewModel = BriefingViewModel()
        let noteA = Note.mock(id: 1, title: "Note A")
        let noteB = Note.mock(id: 7, title: "Note B")

        let connections: [(noteA: Note, noteB: Note, threadAName: String, threadBName: String, explanation: String)] = [
            (noteA, noteB, "Focus Systems", "Daily Habits", "Both about energy management")
        ]

        let cards = viewModel.buildConnectionCards(connections: connections)

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].noteATitle, "Note A")
        XCTAssertEqual(cards[0].noteBTitle, "Note B")
        XCTAssertEqual(cards[0].explanation, "Both about energy management")
    }

    func testBuildFallbackIntro() {
        let viewModel = BriefingViewModel()

        let intro = viewModel.buildFallbackIntro(changedCount: 3, attentionCount: 1, connectionCount: 2)

        XCTAssertTrue(intro.contains("3 new notes"))
        XCTAssertTrue(intro.contains("1 thread needs attention"))
        XCTAssertTrue(intro.contains("2 connections found"))
    }

    func testBuildFallbackIntroEmpty() {
        let viewModel = BriefingViewModel()

        let intro = viewModel.buildFallbackIntro(changedCount: 0, attentionCount: 0, connectionCount: 0)

        XCTAssertEqual(intro, "Nothing new since last time.")
    }

    func testBuildFallbackIntroSingular() {
        let viewModel = BriefingViewModel()

        let intro = viewModel.buildFallbackIntro(changedCount: 1, attentionCount: 0, connectionCount: 1)

        XCTAssertTrue(intro.contains("1 new note"))
        XCTAssertFalse(intro.contains("notes"))
        XCTAssertTrue(intro.contains("1 connection found"))
    }

    func testDaysSinceLastActivity() {
        let viewModel = BriefingViewModel()
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let thread = Thread.mock(lastActivityAt: threeDaysAgo)

        let days = viewModel.daysSinceLastActivity(thread)

        XCTAssertEqual(days, 3)
    }

    func testDaysSinceLastActivityNil() {
        let viewModel = BriefingViewModel()
        let thread = Thread.mock(lastActivityAt: nil)

        let days = viewModel.daysSinceLastActivity(thread)

        XCTAssertEqual(days, 999)
    }
}
