import SeleneShared
import SwiftUI

struct SubprojectSuggestionCard: View {
    let suggestion: SubprojectSuggestion
    let onApprove: () async -> Bool  // Returns true if successful
    let onDismiss: () -> Void
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with lightbulb icon
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Sub-Project Suggestion")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Suggestion text (e.g. "Spin off 'Frontend Work' as its own project?")
            Text(suggestion.suggestionText)
                .font(.headline)

            // Detail text (e.g. "7 tasks share the 'frontend' concept")
            Text(suggestion.detailText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Source project name if available
            if let sourceName = suggestion.sourceProjectName {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text("From: \(sourceName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Buttons
            HStack(spacing: 12) {
                Button(action: {
                    isProcessing = true
                    Task {
                        let success = await onApprove()
                        if !success {
                            isProcessing = false
                        }
                        // If success, card will be removed by parent
                    }
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Create Project")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isProcessing)

                Button(action: onDismiss) {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Not Now")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isProcessing)
            }
            .padding(.top, 4)

            if isProcessing {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Creating project...").font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.yellow.opacity(0.05))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
        .cornerRadius(12)
    }
}
