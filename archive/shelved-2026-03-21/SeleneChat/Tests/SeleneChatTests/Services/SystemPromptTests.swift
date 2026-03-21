import XCTest
import SeleneShared
@testable import SeleneChat

@MainActor
final class SystemPromptTests: XCTestCase {

    func testSystemPromptContainsZenPersonality() {
        let vm = ChatViewModel()
        let prompt = vm.buildSystemPromptForTesting(queryType: .general)

        // Should NOT contain old generic language
        XCTAssertFalse(prompt.contains("personal AI assistant"))
        XCTAssertFalse(prompt.contains("Be conversational and supportive"))

        // Should contain zen personality markers
        XCTAssertTrue(prompt.contains("Never summarize unless asked"))
        XCTAssertTrue(prompt.contains("Cite specific notes"))
    }

    func testSystemPromptContainsCitationEvidence() {
        let vm = ChatViewModel()
        let prompt = vm.buildSystemPromptForTesting(queryType: .knowledge)

        XCTAssertTrue(prompt.contains("cite") || prompt.contains("Cite"))
        XCTAssertTrue(prompt.contains("evidence") || prompt.contains("specific notes"))
    }

    func testSystemPromptContainsContextBlockAwareness() {
        let vm = ChatViewModel()
        let prompt = vm.buildSystemPromptForTesting(queryType: .general)

        XCTAssertTrue(prompt.contains("EMOTIONAL HISTORY"))
        XCTAssertTrue(prompt.contains("TASK HISTORY"))
    }

    func testQuerySpecificPromptForPattern() {
        let vm = ChatViewModel()
        let prompt = vm.buildSystemPromptForTesting(queryType: .pattern)
        XCTAssertTrue(prompt.contains("pattern") || prompt.contains("Pattern"))
    }

    func testQuerySpecificPromptForDeepDive() {
        let vm = ChatViewModel()
        let prompt = vm.buildSystemPromptForTesting(queryType: .deepDive)
        XCTAssertTrue(prompt.contains("ACTION:"))
    }
}
