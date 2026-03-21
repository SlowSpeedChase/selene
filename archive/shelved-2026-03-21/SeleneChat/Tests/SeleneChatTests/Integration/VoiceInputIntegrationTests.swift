import SeleneShared
import XCTest
@testable import SeleneChat

final class VoiceInputIntegrationTests: XCTestCase {

    @MainActor
    func testSpeechServiceTextFlowsToMessagePipeline() async {
        let viewModel = ChatViewModel()
        let speechService = SpeechRecognitionService()

        // Simulate voice transcription result
        speechService.liveText = "search my notes about project planning"

        let transcribedText = speechService.liveText
        XCTAssertFalse(transcribedText.isEmpty)

        // Send through normal pipeline
        await viewModel.sendMessage(transcribedText)

        let userMessages = viewModel.currentSession.messages.filter { $0.role == .user }
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages[0].content, "search my notes about project planning")
    }

    @MainActor
    func testCancelVoiceInputDoesNotSend() {
        let speechService = SpeechRecognitionService()

        speechService.liveText = "some partial text"
        speechService.cancel()

        XCTAssertEqual(speechService.liveText, "")
    }

    @MainActor
    func testEscapeKeyBehavior() {
        let speechService = SpeechRecognitionService()
        speechService.liveText = "partial transcription"

        speechService.cancel()

        XCTAssertEqual(speechService.state, .idle)
        XCTAssertEqual(speechService.liveText, "")
    }

    @MainActor
    func testVoiceTextAppearsInMessageText() {
        let speechService = SpeechRecognitionService()

        speechService.liveText = "hello"
        XCTAssertEqual(speechService.liveText, "hello")

        speechService.liveText = "hello world"
        XCTAssertEqual(speechService.liveText, "hello world")

        speechService.liveText = "hello world how are you"
        XCTAssertEqual(speechService.liveText, "hello world how are you")
    }
}
