import SeleneShared
import XCTest
@testable import SeleneChat

final class SpeechSynthesisServiceTests: XCTestCase {

    // MARK: - Text Cleaning

    @MainActor
    func testStripsBoldMarkdown() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("This is **bold** text")
        XCTAssertEqual(cleaned, "This is bold text")
    }

    @MainActor
    func testStripsItalicMarkdown() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("This is _italic_ text")
        XCTAssertEqual(cleaned, "This is italic text")
    }

    @MainActor
    func testStripsCitationMarkers() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("As mentioned [1] and also [2]")
        XCTAssertEqual(cleaned, "As mentioned and also")
    }

    @MainActor
    func testStripsNoteStyleCitations() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("You wrote about this [Note: 'Morning Routine' - Nov 14]")
        XCTAssertEqual(cleaned, "You wrote about this")
    }

    @MainActor
    func testStripsCodeBlocks() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("Here is code:\n```swift\nlet x = 1\n```\nAnd more text")
        XCTAssertEqual(cleaned, "Here is code:\n\nAnd more text")
    }

    @MainActor
    func testStripsInlineCode() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("Use the `print` function")
        XCTAssertEqual(cleaned, "Use the print function")
    }

    @MainActor
    func testStripsURLs() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("Visit https://example.com for more")
        XCTAssertEqual(cleaned, "Visit for more")
    }

    @MainActor
    func testStripsBulletMarkers() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("- First item\n- Second item")
        XCTAssertEqual(cleaned, "First item\nSecond item")
    }

    @MainActor
    func testStripsNumberedListMarkers() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("1. First\n2. Second")
        XCTAssertEqual(cleaned, "First\nSecond")
    }

    @MainActor
    func testStripsHeadingMarkers() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("## Active Threads\n\nHere are your threads")
        XCTAssertEqual(cleaned, "Active Threads\n\nHere are your threads")
    }

    @MainActor
    func testCollapsesExtraWhitespace() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("word   word")
        XCTAssertEqual(cleaned, "word word")
    }

    @MainActor
    func testCombinedMarkdownStripping() {
        let service = SpeechSynthesisService()
        let cleaned = service.cleanTextForSpeech("**Active Threads** [1]\n\n- _First item_\n- Second [2]")
        XCTAssertEqual(cleaned, "Active Threads\n\nFirst item\nSecond")
    }

    // MARK: - State Management

    @MainActor
    func testInitialStateIsNotSpeaking() {
        let service = SpeechSynthesisService()
        XCTAssertFalse(service.isSpeaking)
    }

    @MainActor
    func testSpeakSetsIsSpeakingTrue() {
        let service = SpeechSynthesisService()
        service.speak(text: "Hello world")
        XCTAssertTrue(service.isSpeaking)
    }

    @MainActor
    func testStopSetsIsSpeakingFalse() {
        let service = SpeechSynthesisService()
        service.speak(text: "Hello world")
        service.stop()
        XCTAssertFalse(service.isSpeaking)
    }

    @MainActor
    func testSpeakWithEmptyTextDoesNotSetSpeaking() {
        let service = SpeechSynthesisService()
        service.speak(text: "")
        XCTAssertFalse(service.isSpeaking)
    }

    @MainActor
    func testSpeakWithOnlyMarkdownDoesNotSetSpeaking() {
        let service = SpeechSynthesisService()
        service.speak(text: "**  **")
        XCTAssertFalse(service.isSpeaking)
    }
}
