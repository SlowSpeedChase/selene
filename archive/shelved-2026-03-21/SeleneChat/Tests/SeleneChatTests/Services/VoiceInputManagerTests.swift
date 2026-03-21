import SeleneShared
import XCTest
@testable import SeleneChat

final class VoiceInputManagerTests: XCTestCase {

    @MainActor
    func testParseVoiceURL() {
        let url = URL(string: "selene://voice")!
        let action = VoiceInputManager.parseURL(url)
        XCTAssertEqual(action, .activateVoice)
    }

    @MainActor
    func testParseCaptureURL() {
        let url = URL(string: "selene://capture")!
        let action = VoiceInputManager.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testParseUnknownURL() {
        let url = URL(string: "selene://something-else")!
        let action = VoiceInputManager.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }

    @MainActor
    func testParseNonSeleneURL() {
        let url = URL(string: "https://example.com")!
        let action = VoiceInputManager.parseURL(url)
        XCTAssertEqual(action, .unknown)
    }
}
