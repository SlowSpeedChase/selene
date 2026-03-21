import SeleneShared
import Foundation
import AppKit

/// Actions that can be triggered via URL scheme
enum VoiceURLAction: Equatable {
    case activateVoice
    case unknown
}

/// Manages voice input activation from URL schemes.
/// Handles `selene://voice` to bring app to front and start listening.
@MainActor
class VoiceInputManager: ObservableObject {
    private let speechService: SpeechRecognitionService

    init(speechService: SpeechRecognitionService) {
        self.speechService = speechService
    }

    /// Parse a selene:// URL into an action
    static func parseURL(_ url: URL) -> VoiceURLAction {
        guard url.scheme == "selene" else { return .unknown }
        switch url.host {
        case "voice": return .activateVoice
        default: return .unknown
        }
    }

    /// Handle an incoming URL
    func handleURL(_ url: URL) {
        let action = VoiceInputManager.parseURL(url)
        switch action {
        case .activateVoice:
            activateVoiceInput()
        case .unknown:
            break
        }
    }

    /// Bring app to front and start voice input
    func activateVoiceInput() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            await speechService.startListening()
        }
    }
}
