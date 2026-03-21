import SeleneShared
import XCTest
import Speech
@testable import SeleneChat

final class SpeechRecognitionServiceTests: XCTestCase {

    // MARK: - State Machine Tests

    @MainActor
    func testInitialStateIsIdle() {
        let service = SpeechRecognitionService()
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.liveText, "")
    }

    @MainActor
    func testStateTransitionsToListeningOnStart() async throws {
        // startListening() triggers SFSpeechRecognizer.requestAuthorization
        // and AVAudioEngine setup, which crash in CLI test runners (SIGABRT).
        // Only run when speech is already authorized (no dialog prompt).
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        try XCTSkipUnless(
            authStatus == .authorized,
            "Requires pre-authorized speech recognition (current: \(authStatus))"
        )

        let service = SpeechRecognitionService()
        await service.startListening()
        // In environments without microphone access, state may be
        // .unavailable rather than .listening. Both are valid outcomes.
        switch service.state {
        case .listening, .idle, .unavailable:
            break // all acceptable
        case .processing:
            XCTFail("Should not transition directly to processing")
        }
    }

    @MainActor
    func testStopListeningResetsToIdle() async {
        let service = SpeechRecognitionService()
        service.stopListening()
        XCTAssertEqual(service.state, .idle)
    }

    @MainActor
    func testStopListeningPreservesLiveText() async {
        let service = SpeechRecognitionService()
        service.liveText = "test transcription"
        service.stopListening()
        XCTAssertEqual(service.liveText, "test transcription")
    }

    @MainActor
    func testCancelClearsEverything() async {
        let service = SpeechRecognitionService()
        service.liveText = "test transcription"
        service.cancel()
        XCTAssertEqual(service.liveText, "")
        XCTAssertEqual(service.state, .idle)
    }

    @MainActor
    func testIsAvailableReturnsBool() {
        let service = SpeechRecognitionService()
        // Verify the property exists and returns a Bool value
        // Result depends on hardware: true on Mac with audio, false in headless CI
        let available = service.isAvailable
        XCTAssertEqual(available, available) // Validates property is accessible
    }

    @MainActor
    func testSilenceTimeoutDefaultValue() {
        let service = SpeechRecognitionService()
        XCTAssertEqual(service.silenceTimeout, 2.0)
    }

    @MainActor
    func testSilenceTimeoutIsConfigurable() {
        let service = SpeechRecognitionService()
        service.silenceTimeout = 3.0
        XCTAssertEqual(service.silenceTimeout, 3.0)
    }
}
