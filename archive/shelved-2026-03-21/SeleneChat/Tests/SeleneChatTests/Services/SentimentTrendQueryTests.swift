import XCTest
import SeleneShared
@testable import SeleneChat

final class SentimentTrendQueryTests: XCTestCase {
    var databaseService: DatabaseService!
    var testDatabasePath: String!

    override func setUp() async throws {
        try await super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        testDatabasePath = tempDir.appendingPathComponent("test_selene_\(UUID().uuidString).db").path
        databaseService = DatabaseService()
        databaseService.databasePath = testDatabasePath
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: testDatabasePath)
        databaseService = nil
        try await super.tearDown()
    }

    func testGetSentimentTrendReturnsEmptyForEmptyDB() async throws {
        let trend = try await databaseService.getSentimentTrend(days: 7)
        XCTAssertEqual(trend.totalNotes, 0)
        XCTAssertTrue(trend.toneCounts.isEmpty)
        XCTAssertNil(trend.averageSentimentScore)
        XCTAssertEqual(trend.periodDays, 7)
    }

    func testGetSentimentTrendReturnsEmptyForZeroDays() async throws {
        let trend = try await databaseService.getSentimentTrend(days: 0)
        XCTAssertEqual(trend.totalNotes, 0)
        XCTAssertTrue(trend.toneCounts.isEmpty)
        XCTAssertNil(trend.averageSentimentScore)
        XCTAssertEqual(trend.periodDays, 0)
    }

    func testGetSentimentTrendReturnsEmptyForNegativeDays() async throws {
        let trend = try await databaseService.getSentimentTrend(days: -1)
        XCTAssertEqual(trend.totalNotes, 0)
        XCTAssertTrue(trend.toneCounts.isEmpty)
        XCTAssertNil(trend.averageSentimentScore)
        XCTAssertEqual(trend.periodDays, -1)
    }

    func testSentimentTrendFormattedOutput() {
        let trend = SentimentTrend(
            toneCounts: ["frustrated": 3, "anxious": 2, "neutral": 5, "calm": 1],
            totalNotes: 11,
            averageSentimentScore: -0.3,
            periodDays: 7
        )
        // Formatted should exclude neutral, sorted by count desc
        let formatted = trend.formatted
        XCTAssertTrue(formatted.contains("frustrated 3x"))
        XCTAssertTrue(formatted.contains("anxious 2x"))
        XCTAssertTrue(formatted.contains("calm 1x"))
        XCTAssertFalse(formatted.contains("neutral"))
    }

    func testSentimentTrendDominantTone() {
        let trend = SentimentTrend(
            toneCounts: ["frustrated": 3, "anxious": 2, "neutral": 5],
            totalNotes: 10,
            averageSentimentScore: -0.4,
            periodDays: 7
        )
        XCTAssertEqual(trend.dominantTone, "frustrated")
    }

    func testSentimentTrendMostlyNeutral() {
        let trend = SentimentTrend(
            toneCounts: ["neutral": 8],
            totalNotes: 8,
            averageSentimentScore: 0.0,
            periodDays: 7
        )
        XCTAssertEqual(trend.formatted, "mostly neutral")
        XCTAssertNil(trend.dominantTone)
    }

    func testSentimentTrendEmptyToneCounts() {
        let trend = SentimentTrend(
            toneCounts: [:],
            totalNotes: 0,
            averageSentimentScore: nil,
            periodDays: 7
        )
        XCTAssertEqual(trend.formatted, "mostly neutral")
        XCTAssertNil(trend.dominantTone)
    }

    func testSentimentTrendHashable() {
        let trend1 = SentimentTrend(
            toneCounts: ["frustrated": 3],
            totalNotes: 3,
            averageSentimentScore: -0.5,
            periodDays: 7
        )
        let trend2 = SentimentTrend(
            toneCounts: ["frustrated": 3],
            totalNotes: 3,
            averageSentimentScore: -0.5,
            periodDays: 7
        )
        XCTAssertEqual(trend1, trend2)

        var set = Set<SentimentTrend>()
        set.insert(trend1)
        set.insert(trend2)
        XCTAssertEqual(set.count, 1)
    }
}
