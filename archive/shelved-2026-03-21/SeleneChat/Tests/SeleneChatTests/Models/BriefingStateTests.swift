import SeleneShared
import XCTest
@testable import SeleneChat

final class BriefingStateTests: XCTestCase {
    func testBriefingCardTypes() {
        let changedCard = BriefingCard.whatChanged(
            noteTitle: "Planning Deep Work",
            noteId: 1,
            threadName: "Focus Systems",
            threadId: 5,
            date: Date(),
            primaryTheme: "productivity",
            energyLevel: "high"
        )

        XCTAssertEqual(changedCard.cardType, .whatChanged)
        XCTAssertEqual(changedCard.noteTitle, "Planning Deep Work")
        XCTAssertEqual(changedCard.threadName, "Focus Systems")
    }

    func testNeedsAttentionCard() {
        let attentionCard = BriefingCard.needsAttention(
            threadName: "Focus Systems",
            threadId: 5,
            reason: "No new notes in 6 days",
            noteCount: 8,
            openTaskCount: 3
        )

        XCTAssertEqual(attentionCard.cardType, .needsAttention)
        XCTAssertEqual(attentionCard.reason, "No new notes in 6 days")
        XCTAssertEqual(attentionCard.openTaskCount, 3)
    }

    func testConnectionCard() {
        let connectionCard = BriefingCard.connection(
            noteATitle: "Planning Deep Work",
            noteAId: 1,
            threadAName: "Focus Systems",
            noteBTitle: "Morning Routine Experiment",
            noteBId: 7,
            threadBName: "Daily Habits",
            explanation: "Both explore structuring time around energy levels"
        )

        XCTAssertEqual(connectionCard.cardType, .connection)
        XCTAssertEqual(connectionCard.explanation, "Both explore structuring time around energy levels")
    }

    func testStructuredBriefing() {
        let briefing = StructuredBriefing(
            intro: "Busy day yesterday, 4 notes across 2 threads.",
            whatChanged: [],
            needsAttention: [],
            connections: [],
            generatedAt: Date()
        )

        XCTAssertTrue(briefing.whatChanged.isEmpty)
        XCTAssertFalse(briefing.intro.isEmpty)
        XCTAssertTrue(briefing.isEmpty)
    }

    func testStructuredBriefingStatus() {
        let briefing = StructuredBriefing(
            intro: "Test",
            whatChanged: [],
            needsAttention: [],
            connections: [],
            generatedAt: Date()
        )
        let status = BriefingStatus.loaded(briefing)

        if case .loaded(let b) = status {
            XCTAssertEqual(b.intro, "Test")
        } else {
            XCTFail("Expected loaded status")
        }
    }

    func testBriefingStatusEquatable() {
        let status1 = BriefingStatus.loading
        let status2 = BriefingStatus.loading
        XCTAssertEqual(status1, status2)

        let status3 = BriefingStatus.notLoaded
        XCTAssertNotEqual(status1, status3)
    }

    func testBriefingStateInitialValue() {
        let state = BriefingState()
        if case .notLoaded = state.status {
            // expected
        } else {
            XCTFail("Expected notLoaded initial state")
        }
    }

    func testStructuredBriefingIsNotEmptyWithCards() {
        let card = BriefingCard.whatChanged(
            noteTitle: "Test", noteId: 1, threadName: nil, threadId: nil,
            date: Date(), primaryTheme: nil, energyLevel: nil
        )
        let briefing = StructuredBriefing(
            intro: "Hello",
            whatChanged: [card],
            needsAttention: [],
            connections: [],
            generatedAt: Date()
        )
        XCTAssertFalse(briefing.isEmpty)
    }

    func testEnergyEmoji() {
        let high = BriefingCard.whatChanged(noteTitle: "T", noteId: 1, threadName: nil, threadId: nil, date: Date(), primaryTheme: nil, energyLevel: "high")
        XCTAssertEqual(high.energyEmoji, "\u{26A1}")

        let low = BriefingCard.whatChanged(noteTitle: "T", noteId: 1, threadName: nil, threadId: nil, date: Date(), primaryTheme: nil, energyLevel: "low")
        XCTAssertEqual(low.energyEmoji, "\u{1FAAB}")

        let none = BriefingCard.whatChanged(noteTitle: "T", noteId: 1, threadName: nil, threadId: nil, date: Date(), primaryTheme: nil, energyLevel: nil)
        XCTAssertEqual(none.energyEmoji, "")
    }
}
