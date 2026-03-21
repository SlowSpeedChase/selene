import SeleneShared
import XCTest
@testable import SeleneChat

#if DEBUG

final class ActionTrackerTests: XCTestCase {

    func test_track_storesAction() {
        // Arrange
        let tracker = ActionTracker()

        // Act
        tracker.track(action: "tappedThread", params: ["id": "abc-123"])

        // Assert
        let actions = tracker.recentActions
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?["action"] as? String, "tappedThread")
    }

    func test_track_limitsToMaxCount() {
        // Arrange
        let tracker = ActionTracker(maxActions: 3)

        // Act
        tracker.track(action: "action1", params: nil)
        tracker.track(action: "action2", params: nil)
        tracker.track(action: "action3", params: nil)
        tracker.track(action: "action4", params: nil)

        // Assert
        let actions = tracker.recentActions
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.last?["action"] as? String, "action4")
    }

    func test_track_includesTimestamp() {
        // Arrange
        let tracker = ActionTracker()

        // Act
        tracker.track(action: "test", params: nil)

        // Assert
        let action = tracker.recentActions.first
        XCTAssertNotNil(action?["time"])
    }

    func test_conformsToDebugSnapshotProvider() {
        // Arrange
        let tracker = ActionTracker()
        tracker.track(action: "test", params: ["key": "value"])

        // Act
        let snapshot = tracker.debugSnapshot()

        // Assert
        XCTAssertNotNil(snapshot["recentActions"])
    }
}

#endif
