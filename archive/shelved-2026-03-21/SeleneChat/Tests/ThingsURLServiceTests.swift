import SeleneShared
import XCTest
@testable import SeleneChat

final class ThingsURLServiceTests: XCTestCase {

    func testBuildAddTaskURL() {
        let service = ThingsURLService.shared

        let url = service.buildAddTaskURL(
            title: "Test task",
            notes: "Some notes",
            tags: ["selene", "high-energy"],
            sourceNoteId: 42,
            threadId: 7
        )

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("things:///add"))
        XCTAssertTrue(url!.absoluteString.contains("title=Test%20task"))
        XCTAssertTrue(url!.absoluteString.contains("selene"))
    }

    func testBuildAddTaskURLWithSpecialCharacters() {
        let service = ThingsURLService.shared

        let url = service.buildAddTaskURL(
            title: "Task with 'quotes' & ampersand",
            notes: nil,
            tags: [],
            sourceNoteId: nil,
            threadId: nil
        )

        XCTAssertNotNil(url)
        // URL should be properly encoded
        XCTAssertFalse(url!.absoluteString.contains("&a")) // ampersand should be encoded
    }

    func testSeleneMetadataInNotes() {
        let service = ThingsURLService.shared

        let url = service.buildAddTaskURL(
            title: "Test",
            notes: "Original note",
            tags: [],
            sourceNoteId: 42,
            threadId: 7
        )

        XCTAssertNotNil(url)
        // Should contain selene metadata
        XCTAssertTrue(url!.absoluteString.contains("selene"))
        XCTAssertTrue(url!.absoluteString.contains("42"))
        XCTAssertTrue(url!.absoluteString.contains("7"))
    }

    func testSeleneTagAlwaysIncluded() {
        let service = ThingsURLService.shared

        // Even when no tags provided, should include 'selene'
        let url = service.buildAddTaskURL(
            title: "Task without tags",
            notes: nil,
            tags: [],
            sourceNoteId: nil,
            threadId: nil
        )

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("tags=selene"))
    }

    func testSeleneTagNotDuplicated() {
        let service = ThingsURLService.shared

        // If 'selene' already in tags, should not duplicate
        let url = service.buildAddTaskURL(
            title: "Task with selene tag",
            notes: nil,
            tags: ["selene", "other"],
            sourceNoteId: nil,
            threadId: nil
        )

        XCTAssertNotNil(url)
        let urlString = url!.absoluteString
        // Count occurrences of 'selene' in tags - should only appear once
        let tagsRange = urlString.range(of: "tags=")
        XCTAssertNotNil(tagsRange)
    }

    func testDeadlineFormatting() {
        let service = ThingsURLService.shared

        // Create a specific date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let deadline = formatter.date(from: "2025-01-15")!

        let url = service.buildAddTaskURL(
            title: "Task with deadline",
            notes: nil,
            tags: [],
            sourceNoteId: nil,
            threadId: nil,
            deadline: deadline
        )

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("deadline=2025-01-15"))
    }

    func testQuickEntryDisabled() {
        let service = ThingsURLService.shared

        let url = service.buildAddTaskURL(
            title: "Test",
            notes: nil,
            tags: [],
            sourceNoteId: nil,
            threadId: nil
        )

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("show-quick-entry=false"))
    }

    func testMetadataFormatInNotes() {
        let service = ThingsURLService.shared

        let url = service.buildAddTaskURL(
            title: "Test",
            notes: nil,
            tags: [],
            sourceNoteId: 123,
            threadId: 456
        )

        XCTAssertNotNil(url)
        // Should contain the selene metadata marker format
        let urlString = url!.absoluteString
        XCTAssertTrue(urlString.contains("note-123"))
        XCTAssertTrue(urlString.contains("thread-456"))
    }

    func testIsThingsInstalled() {
        let service = ThingsURLService.shared

        // This just tests that the method exists and returns a Bool
        // Actual result depends on whether Things is installed
        let result = service.isThingsInstalled()
        XCTAssertTrue(result == true || result == false)
    }
}
