import SeleneShared
import XCTest
import AppKit
@testable import SeleneChat

@MainActor
final class AppLifecycleTests: XCTestCase {
    func testActivationPolicyAccessory() {
        let policy = NSApplication.ActivationPolicy.accessory
        XCTAssertEqual(policy, .accessory)
    }

    func testActivationPolicyRegular() {
        let policy = NSApplication.ActivationPolicy.regular
        XCTAssertEqual(policy, .regular)
    }

    func testWindowCloseShouldNotQuit() {
        // AppDelegate returns false for applicationShouldTerminateAfterLastWindowClosed
        let delegate = AppDelegate()
        let result = delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        XCTAssertFalse(result)
    }
}
