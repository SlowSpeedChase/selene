import SeleneShared
import XCTest
@testable import SeleneChat

/// Mock TTS that records speak/stop calls without producing audio.
@MainActor
final class MockSpeechSynthesisService: SpeechSynthesizing {
    var isSpeaking: Bool = false
    var lastSpokenText: String?
    var speakCallCount: Int = 0
    var stopCallCount: Int = 0

    func speak(text: String) {
        lastSpokenText = text
        speakCallCount += 1
        isSpeaking = true
    }

    func stop() {
        stopCallCount += 1
        isSpeaking = false
    }
}

final class VoiceConversationIntegrationTests: XCTestCase {

    @MainActor
    func testVoiceOriginatedMessageFlaggedCorrectly() async {
        let viewModel = ChatViewModel()
        let mockTTS = MockSpeechSynthesisService()
        viewModel.speechSynthesisService = mockTTS

        // Send a voice-originated message
        await viewModel.sendMessage("test voice", voiceOriginated: true)

        let userMessage = viewModel.currentSession.messages.first { $0.role == .user }
        XCTAssertNotNil(userMessage)
        XCTAssertTrue(userMessage!.voiceOriginated)
    }

    @MainActor
    func testTypedMessageNotFlagged() async {
        let viewModel = ChatViewModel()
        let mockTTS = MockSpeechSynthesisService()
        viewModel.speechSynthesisService = mockTTS

        await viewModel.sendMessage("test typed", voiceOriginated: false)

        let userMessage = viewModel.currentSession.messages.first { $0.role == .user }
        XCTAssertNotNil(userMessage)
        XCTAssertFalse(userMessage!.voiceOriginated)
    }

    @MainActor
    func testTypedMessageDoesNotTriggerTTS() async {
        let viewModel = ChatViewModel()
        let mockTTS = MockSpeechSynthesisService()
        viewModel.speechSynthesisService = mockTTS

        await viewModel.sendMessage("test typed", voiceOriginated: false)

        XCTAssertEqual(mockTTS.speakCallCount, 0)
    }

    @MainActor
    func testDefaultVoiceOriginatedIsFalse() async {
        let viewModel = ChatViewModel()

        // No voiceOriginated param = defaults to false
        await viewModel.sendMessage("test default")

        let userMessage = viewModel.currentSession.messages.first { $0.role == .user }
        XCTAssertNotNil(userMessage)
        XCTAssertFalse(userMessage!.voiceOriginated)
    }

    @MainActor
    func testMockTTSStopResetsState() {
        let mockTTS = MockSpeechSynthesisService()
        mockTTS.speak(text: "hello")
        XCTAssertTrue(mockTTS.isSpeaking)
        mockTTS.stop()
        XCTAssertFalse(mockTTS.isSpeaking)
        XCTAssertEqual(mockTTS.stopCallCount, 1)
    }
}
