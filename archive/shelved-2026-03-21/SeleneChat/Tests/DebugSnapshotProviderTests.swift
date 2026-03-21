import SeleneShared
import XCTest
@testable import SeleneChat

#if DEBUG

final class DebugSnapshotProviderTests: XCTestCase {

    func test_mockProvider_returnsSnapshot() {
        // Arrange
        let provider = MockSnapshotProvider()

        // Act
        let snapshot = provider.debugSnapshot()

        // Assert
        XCTAssertEqual(snapshot["testKey"] as? String, "testValue")
    }

    func test_snapshot_isSerializableToJSON() throws {
        // Arrange
        let provider = MockSnapshotProvider()
        let snapshot = provider.debugSnapshot()

        // Act
        let data = try JSONSerialization.data(withJSONObject: snapshot)

        // Assert
        XCTAssertGreaterThan(data.count, 0)
    }
}

// Mock implementation for testing
class MockSnapshotProvider: DebugSnapshotProvider {
    func debugSnapshot() -> [String: Any] {
        return ["testKey": "testValue", "count": 42]
    }
}

#endif
