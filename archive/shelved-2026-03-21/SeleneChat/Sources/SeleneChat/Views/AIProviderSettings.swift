import SeleneShared
// SeleneChat/Sources/Views/AIProviderSettings.swift
import SwiftUI

struct AIProviderSettings: View {
    @ObservedObject var providerService: AIProviderService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("Planning Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
            }

            Divider()

            // Default Provider Toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Default AI Provider")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Provider", selection: $providerService.globalDefault) {
                    Label("Local (Ollama)", systemImage: "house.fill")
                        .tag(AIProvider.local)
                    Label("Cloud (Claude)", systemImage: "cloud.fill")
                        .tag(AIProvider.cloud)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Provider Info
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider Info")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Label("Ollama", systemImage: "house.fill")
                    Spacer()
                    Text("localhost:11434")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Claude API", systemImage: "cloud.fill")
                    Spacer()
                    if ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("API key set")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("API key not found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
    }
}
