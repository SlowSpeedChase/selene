import SeleneShared
import XCTest
@testable import SeleneChat

#if DEBUG

final class DebugSystemIntegrationTests: XCTestCase {

    let logPath = "/tmp/selenechat-debug-integration-test.log"
    let requestPath = "/tmp/selenechat-snapshot-request-integration-test"
    let outputPath = "/tmp/selenechat-snapshot-integration-test.json"

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: logPath)
        try? FileManager.default.removeItem(atPath: requestPath)
        try? FileManager.default.removeItem(atPath: outputPath)
        super.tearDown()
    }

    func test_fullDebugWorkflow() {
        // Arrange
        let logger = DebugLogger(logPath: logPath)
        let snapshotService = DebugSnapshotService(requestPath: requestPath, outputPath: outputPath)
        let actionTracker = ActionTracker()

        snapshotService.registerProvider(named: "actions", provider: actionTracker)

        // Act - simulate app activity
        logger.log(.state, "Test started")
        actionTracker.track(action: "testAction", params: ["key": "value"])
        logger.log(.nav, "Navigated to TestView")

        // Allow async operations to complete
        Thread.sleep(forTimeInterval: 0.1)

        // Trigger snapshot
        FileManager.default.createFile(atPath: requestPath, contents: nil)
        snapshotService.checkForRequest()

        // Assert - verify all files created
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath), "Log file should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath), "Snapshot file should exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestPath), "Request file should be deleted")

        // Verify log content
        let logContent = try? String(contentsOfFile: logPath, encoding: .utf8)
        XCTAssertTrue(logContent?.contains("Test started") ?? false)
        XCTAssertTrue(logContent?.contains("NAV") ?? false)

        // Verify snapshot content
        let snapshotContent = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(snapshotContent?.contains("testAction") ?? false)
        XCTAssertTrue(snapshotContent?.contains("timestamp") ?? false)
    }
}

#endif
