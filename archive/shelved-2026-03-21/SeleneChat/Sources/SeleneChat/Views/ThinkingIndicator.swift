import SeleneShared
import SwiftUI

/// Fun, animated indicator showing Selene is thinking/processing with Ollama
struct ThinkingIndicator: View {
    @State private var animationPhase = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var rotation: Double = 0

    let messages = [
        "Analyzing your notes...",
        "Finding patterns...",
        "Connecting concepts...",
        "Thinking deeply...",
        "Processing with Ollama...",
        "Reviewing themes...",
        "Synthesizing insights..."
    ]

    var body: some View {
        HStack(spacing: 12) {
            // Animated brain/thinking icon
            ZStack {
                // Outer pulse ring
                Circle()
                    .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .scaleEffect(pulseScale)
                    .opacity(2 - pulseScale)

                // Inner spinning gradient
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.purple, .blue, .purple],
                            center: .center,
                            angle: .degrees(rotation)
                        )
                    )
                    .frame(width: 30, height: 30)

                // Brain emoji or sparkle
                Text("🧠")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(rotation / 2))
            }
            .onAppear {
                // Pulse animation
                withAnimation(
                    .easeInOut(duration: 1.5)
                    .repeatForever(autoreverses: false)
                ) {
                    pulseScale = 1.5
                }

                // Rotation animation
                withAnimation(
                    .linear(duration: 3.0)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                // Cycling message
                Text(messages[animationPhase % messages.count])
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .transition(.opacity)

                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 6, height: 6)
                            .opacity(dotOpacity(for: index))
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.purple.opacity(0.1))
        )
        .onAppear {
            // Cycle through messages
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationPhase += 1
                }
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let cycle = (animationPhase % 6) // 6 phases for 3 dots (2 per dot)
        if cycle == index * 2 || cycle == (index * 2 + 1) {
            return 1.0
        }
        return 0.3
    }
}

/// Compact version for inline use
struct ThinkingIndicatorCompact: View {
    @State private var dotPhase = 0

    var body: some View {
        HStack(spacing: 6) {
            Text("🧠")
                .font(.system(size: 14))

            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 4, height: 4)
                        .opacity(dotPhase == index ? 1.0 : 0.3)
                }
            }

            Text("thinking...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    dotPhase = (dotPhase + 1) % 3
                }
            }
        }
    }
}
