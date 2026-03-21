import XCTest
@testable import SeleneChat

final class ThingsSyncTests: XCTestCase {

    func testParseTaskStatusResponseCompleted() {
        let json = """
        {"id": "ABC123", "status": "completed", "name": "Test Task", "completion_date": "2026-02-13", "modification_date": "2026-02-13", "creation_date": "2026-02-10", "project": null, "area": null, "tags": ["selene"]}
        """

        let result = ThingsURLService.parseTaskStatusResponse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "completed")
        XCTAssertEqual(result?.name, "Test Task")
        XCTAssertNotNil(result?.completionDate)
    }

    func testParseTaskStatusResponseOpen() {
        let json = """
        {"id": "DEF456", "status": "open", "name": "Open Task", "completion_date": null, "modification_date": "2026-02-13", "creation_date": "2026-02-10", "project": null, "area": null, "tags": []}
        """

        let result = ThingsURLService.parseTaskStatusResponse(json)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.status, "open")
        XCTAssertNil(result?.completionDate)
    }

    func testParseTaskStatusResponseError() {
        let json = """
        {"error": "Task not found: XYZ789"}
        """

        let result = ThingsURLService.parseTaskStatusResponse(json)
        XCTAssertNil(result, "Should return nil for error responses")
    }

    func testParseTaskStatusResponseInvalidJSON() {
        let result = ThingsURLService.parseTaskStatusResponse("not json")
        XCTAssertNil(result)
    }
}
