import SeleneShared
import XCTest
@testable import SeleneChat

final class PromptVoiceAlignmentTests: XCTestCase {

    func testDeepDiveNoWordLimit() {
        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(),
            notes: [Note.mock()]
        )
        XCTAssertFalse(prompt.contains("200 words"))
        XCTAssertFalse(prompt.contains("150 words"))
        XCTAssertFalse(prompt.contains("100 words"))
    }

    func testSynthesisNoWordLimit() {
        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(
            threads: [Thread.mock()],
            notesPerThread: [1: [Note.mock()]]
        )
        XCTAssertFalse(prompt.contains("200 words"))
    }

    func testBriefingUsesZenVoice() {
        let builder = BriefingContextBuilder()
        let prompt = builder.buildSystemPrompt(for: .whatChanged)
        XCTAssertTrue(prompt.lowercased().contains("ask") || prompt.lowercased().contains("question"))
    }

    func testDeepDiveHasContextBlockAwareness() {
        let builder = DeepDivePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(),
            notes: [Note.mock()]
        )
        XCTAssertTrue(prompt.contains("EMOTIONAL HISTORY") || prompt.contains("CONTEXT BLOCKS"))
    }

    func testSynthesisPresentsOptions() {
        let builder = SynthesisPromptBuilder()
        let prompt = builder.buildSynthesisPrompt(
            threads: [Thread.mock()],
            notesPerThread: [1: [Note.mock()]]
        )
        XCTAssertTrue(prompt.contains("2-3") || prompt.contains("options"))
    }
}
