import SeleneShared
import Foundation
import Speech
import AVFoundation

/// Voice state for UI binding
enum VoiceState: Equatable {
    case idle
    case listening
    case processing // TODO: Wire up in future phase (e.g., post-transcription processing)
    case unavailable(reason: String)
}

/// Wraps Apple's SFSpeechRecognizer for on-device speech-to-text.
/// All processing happens on-device -- no audio data leaves the Mac.
@MainActor
class SpeechRecognitionService: ObservableObject {
    @Published var liveText: String = ""
    @Published var state: VoiceState = .idle
    @Published var silenceTimeout: TimeInterval = 2.0

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var silenceTimer: Task<Void, Never>?

    var isAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer?.supportsOnDeviceRecognition = true
    }

    /// Request microphone and speech recognition permissions.
    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard speechAuthorized else {
            state = .unavailable(reason: "Speech recognition not authorized. Enable in System Settings > Privacy & Security > Speech Recognition.")
            return false
        }

        return true
    }

    /// Start listening and streaming transcription to `liveText`.
    func startListening() async {
        guard state == .idle else { return }

        let authorized = await requestPermissions()
        guard authorized else { return }

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state = .unavailable(reason: "Speech recognition is not available on this device.")
            return
        }

        let audioEngine: AVAudioEngine
        do {
            audioEngine = AVAudioEngine()
            // Accessing inputNode can crash if no audio hardware is available
            // (e.g. in CLI test runner). Guard with a format check.
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0 else {
                state = .unavailable(reason: "No audio input available.")
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true
            self.recognitionRequest = request

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                request.append(buffer)
            }

            try audioEngine.start()
            self.audioEngine = audioEngine

            state = .listening
            liveText = ""

            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    if let result {
                        self.liveText = result.bestTranscription.formattedString
                        self.resetSilenceTimer()

                        if result.isFinal {
                            self.finishListening()
                        }
                    }

                    if let error {
                        let nsError = error as NSError
                        // Code 216 = no speech detected, which is not a real error
                        if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                            return
                        }
                        self.stopListening()
                    }
                }
            }

            resetSilenceTimer()
        } catch {
            state = .unavailable(reason: "Could not start audio engine: \(error.localizedDescription)")
            return
        }
    }

    /// Stop listening. Keeps liveText for user review.
    func stopListening() {
        silenceTimer?.cancel()
        silenceTimer = nil
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        state = .idle
    }

    /// Cancel listening and clear all text.
    func cancel() {
        stopListening()
        liveText = ""
    }

    private func finishListening() {
        stopListening()
    }

    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        silenceTimer = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(self.silenceTimeout))
            guard !Task.isCancelled else { return }
            self.finishListening()
        }
    }
}
