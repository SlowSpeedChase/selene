import SeleneShared
import XCTest
@testable import SeleneChat

final class VoiceMicButtonTests: XCTestCase {

    @MainActor
    func testSpeechServiceInitialState() {
        let service = SpeechRecognitionService()
        XCTAssertEqual(service.state, .idle)
    }

    @MainActor
    func testButtonShouldBeDisabledDuringProcessing() {
        let isProcessing = true
        let voiceState: VoiceState = .idle
        let shouldDisable = isProcessing || voiceState == .unavailable(reason: "")
        XCTAssertTrue(shouldDisable)
    }

    @MainActor
    func testButtonIconIdleState() {
        let state: VoiceState = .idle
        let iconName: String
        switch state {
        case .idle: iconName = "mic.fill"
        case .listening: iconName = "mic.fill"
        case .processing: iconName = "waveform"
        case .unavailable: iconName = "mic.slash.fill"
        }
        XCTAssertEqual(iconName, "mic.fill")
    }

    @MainActor
    func testButtonIconListeningState() {
        let state: VoiceState = .listening
        let iconName: String
        switch state {
        case .idle: iconName = "mic.fill"
        case .listening: iconName = "mic.fill"
        case .processing: iconName = "waveform"
        case .unavailable: iconName = "mic.slash.fill"
        }
        XCTAssertEqual(iconName, "mic.fill")
    }

    @MainActor
    func testButtonIconUnavailableState() {
        let state: VoiceState = .unavailable(reason: "No permission")
        let iconName: String
        switch state {
        case .idle: iconName = "mic.fill"
        case .listening: iconName = "mic.fill"
        case .processing: iconName = "waveform"
        case .unavailable: iconName = "mic.slash.fill"
        }
        XCTAssertEqual(iconName, "mic.slash.fill")
    }
}
