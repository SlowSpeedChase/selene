import SeleneShared
import XCTest
@testable import SeleneChat

#if DEBUG

final class DebugSnapshotServiceTests: XCTestCase {

    let requestPath = "/tmp/selenechat-snapshot-request-test"
    let outputPath = "/tmp/selenechat-snapshot-test.json"

    override func setUp() {
        super.setUp()
        cleanup()
    }

    override func tearDown() {
        cleanup()
        super.tearDown()
    }

    private func cleanup() {
        try? FileManager.default.removeItem(atPath: requestPath)
        try? FileManager.default.removeItem(atPath: outputPath)
    }

    func test_generateSnapshot_writesJSONFile() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )
        let mockProvider = TestMockSnapshotProvider()
        service.registerProvider(named: "mock", provider: mockProvider)

        // Act
        service.generateSnapshot()

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))

        let content = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("testKey") ?? false)
    }

    func test_generateSnapshot_includesTimestamp() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )

        // Act
        service.generateSnapshot()

        // Assert
        let content = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(content?.contains("timestamp") ?? false)
    }

    func test_checkForRequest_deletesRequestFile() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )

        // Create request file
        FileManager.default.createFile(atPath: requestPath, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestPath))

        // Act
        service.checkForRequest()

        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestPath))
    }

    func test_checkForRequest_generatesSnapshotWhenFileExists() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )
        let mockProvider = TestMockSnapshotProvider()
        service.registerProvider(named: "mock", provider: mockProvider)

        // Create request file
        FileManager.default.createFile(atPath: requestPath, contents: nil)

        // Act
        service.checkForRequest()

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
    }

    func test_checkForRequest_doesNothingWhenNoRequestFile() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )

        // Ensure no request file exists
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestPath))

        // Act
        service.checkForRequest()

        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputPath))
    }

    func test_multipleProviders_allIncludedInSnapshot() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )
        service.registerProvider(named: "provider1", provider: TestMockSnapshotProvider())
        service.registerProvider(named: "provider2", provider: AnotherMockSnapshotProvider())

        // Act
        service.generateSnapshot()

        // Assert
        let content = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("provider1") ?? false)
        XCTAssertTrue(content?.contains("provider2") ?? false)
        XCTAssertTrue(content?.contains("testKey") ?? false)
        XCTAssertTrue(content?.contains("anotherKey") ?? false)
    }
}

// Test-specific mock provider (named differently to avoid conflicts)
class TestMockSnapshotProvider: DebugSnapshotProvider {
    func debugSnapshot() -> [String: Any] {
        return ["testKey": "testValue", "count": 42]
    }
}

class AnotherMockSnapshotProvider: DebugSnapshotProvider {
    func debugSnapshot() -> [String: Any] {
        return ["anotherKey": "anotherValue"]
    }
}

#endif
