import SeleneShared
import SwiftUI

/// Push-to-talk microphone button for voice input.
/// Tap to start/stop listening. Shows pulsing animation while recording.
struct VoiceMicButton: View {
    @ObservedObject var speechService: SpeechRecognitionService
    let isDisabled: Bool

    var body: some View {
        Button(action: toggleListening) {
            ZStack {
                if speechService.state == .listening {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                }

                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(iconColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isUnavailable)
        .help(helpText)
        .onChange(of: speechService.state) { _, newState in
            if newState == .listening {
                pulseScale = 1.3
            } else {
                pulseScale = 1.0
            }
        }
    }

    @State private var pulseScale: CGFloat = 1.0

    private var iconName: String {
        switch speechService.state {
        case .idle: return "mic.fill"
        case .listening: return "mic.fill"
        case .processing: return "waveform"
        case .unavailable: return "mic.slash.fill"
        }
    }

    private var iconColor: Color {
        switch speechService.state {
        case .idle: return .secondary
        case .listening: return .red
        case .processing: return .orange
        case .unavailable: return .gray
        }
    }

    private var isUnavailable: Bool {
        if case .unavailable = speechService.state { return true }
        return false
    }

    private var helpText: String {
        switch speechService.state {
        case .idle: return "Click to start voice input"
        case .listening: return "Listening... Click to stop"
        case .processing: return "Processing speech..."
        case .unavailable(let reason): return reason
        }
    }

    private func toggleListening() {
        Task {
            switch speechService.state {
            case .idle:
                await speechService.startListening()
            case .listening:
                speechService.stopListening()
            default:
                break
            }
        }
    }
}
