import XCTest
import SeleneShared

final class ThreadDigestTests: XCTestCase {
    func testThreadHasDigestProperty() {
        let thread = Thread.mock(
            threadDigest: "This thread started as exploration of morning routines and evolved into a daily habits system.",
            emotionalCharge: "motivated"
        )
        XCTAssertEqual(thread.threadDigest, "This thread started as exploration of morning routines and evolved into a daily habits system.")
        XCTAssertEqual(thread.emotionalCharge, "motivated")
    }

    func testThreadDigestDefaultsToNil() {
        let thread = Thread.mock()
        XCTAssertNil(thread.threadDigest)
        XCTAssertNil(thread.emotionalCharge)
    }
}
