import SeleneShared
import Foundation
import AVFoundation

/// Protocol for text-to-speech, enabling test injection.
@MainActor
protocol SpeechSynthesizing: AnyObject {
    var isSpeaking: Bool { get }
    func speak(text: String)
    func stop()
}

/// Wraps AVSpeechSynthesizer for on-device text-to-speech.
/// Uses system-configured voice from System Settings > Accessibility > Spoken Content.
@MainActor
class SpeechSynthesisService: NSObject, ObservableObject, SpeechSynthesizing {
    @Published var isSpeaking: Bool = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String) {
        // Stop any in-progress speech first
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let cleaned = cleanTextForSpeech(text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// Strip markdown, citations, code blocks, and URLs for natural speech.
    func cleanTextForSpeech(_ text: String) -> String {
        var result = text

        // Remove code blocks (```...```)
        result = result.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: "",
            options: .regularExpression
        )

        // Remove inline code (`...`)
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )

        // Remove Note-style citations [Note: 'Title' - Date]
        result = result.replacingOccurrences(
            of: "\\[Note:[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )

        // Remove numeric citations [1], [2], etc.
        result = result.replacingOccurrences(
            of: "\\[\\d+\\]",
            with: "",
            options: .regularExpression
        )

        // Remove URLs
        result = result.replacingOccurrences(
            of: "https?://\\S+",
            with: "",
            options: .regularExpression
        )

        // Remove heading markers (## ...)
        result = result.replacingOccurrences(
            of: "(?m)^#{1,6}\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove bold (**text** or __text__)
        result = result.replacingOccurrences(
            of: "\\*\\*([^*]+)\\*\\*",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "__([^_]+)__",
            with: "$1",
            options: .regularExpression
        )

        // Remove italic (_text_ or *text*) — single markers
        result = result.replacingOccurrences(
            of: "(?<![\\w*])\\*([^*]+)\\*(?![\\w*])",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "(?<![\\w_])_([^_]+)_(?![\\w_])",
            with: "$1",
            options: .regularExpression
        )

        // Remove bullet markers (- or * at start of line)
        result = result.replacingOccurrences(
            of: "(?m)^[\\-\\*]\\s+",
            with: "",
            options: .regularExpression
        )

        // Remove numbered list markers (1. 2. etc.)
        result = result.replacingOccurrences(
            of: "(?m)^\\d+\\.\\s+",
            with: "",
            options: .regularExpression
        )

        // Collapse multiple spaces into one
        result = result.replacingOccurrences(
            of: " {2,}",
            with: " ",
            options: .regularExpression
        )

        // Trim lines
        result = result
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")

        // Collapse 3+ newlines to 2
        result = result.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
