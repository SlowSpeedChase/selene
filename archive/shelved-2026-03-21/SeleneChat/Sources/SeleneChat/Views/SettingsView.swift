import SeleneShared
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @ObservedObject private var providerService = AIProviderService.shared
    @State private var tempDatabasePath: String = ""
    @State private var showingFilePicker = false

    var body: some View {
        Form {
            Section("AI Provider") {
                Picker("Default Provider", selection: $providerService.globalDefault) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Label(provider.displayName, systemImage: provider.systemImage)
                            .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)

                HStack(spacing: 8) {
                    Text(providerService.globalDefault.icon)
                    Text(providerService.globalDefault == .local
                        ? "Private, runs on your Mac. Best for sensitive content."
                        : "Cloud AI, better reasoning. No personal data sent.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)

                Text("You can override this per conversation in the Planning tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Database") {
                // Environment mode indicator
                HStack {
                    Text(DatabaseService.isRunningFromAppBundle() ? "Production" : "Development")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            DatabaseService.isRunningFromAppBundle()
                                ? Color.green.opacity(0.2)
                                : Color.orange.opacity(0.2)
                        )
                        .foregroundColor(DatabaseService.isRunningFromAppBundle() ? .green : .orange)
                        .cornerRadius(4)
                    Spacer()
                }

                HStack {
                    TextField("Database Path", text: $tempDatabasePath)
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)

                    Button("Browse...") {
                        showFilePicker()
                    }
                }

                HStack {
                    Image(systemName: databaseService.isConnected ? "circle.fill" : "circle")
                        .foregroundColor(databaseService.isConnected ? .green : .red)

                    Text(databaseService.isConnected ? "Connected" : "Not Connected")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Test Connection") {
                        testConnection()
                    }
                }

                Text("Path to your Selene SQLite database (selene.db)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Privacy") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy Tiers")
                        .font(.headline)

                    privacyTierRow(
                        icon: "🔒",
                        title: "On-Device",
                        description: "Apple Intelligence processes data locally. Nothing leaves your device."
                    )

                    privacyTierRow(
                        icon: "🔐",
                        title: "Private Cloud",
                        description: "Apple Private Cloud Compute for complex queries. End-to-end encrypted."
                    )

                    privacyTierRow(
                        icon: "🌐",
                        title: "External",
                        description: "Claude API for non-sensitive planning/technical queries."
                    )
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0 (Phase 1)")
                LabeledContent("Build", value: "Foundation")

                Text("Selene Chat is a privacy-focused chatbot for interacting with your Selene process notes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 500)
        .onAppear {
            tempDatabasePath = databaseService.databasePath
        }
    }

    private func privacyTierRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func showFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.database]
        panel.message = "Select your Selene database file (selene.db)"

        if panel.runModal() == .OK {
            if let url = panel.url {
                tempDatabasePath = url.path
                databaseService.databasePath = url.path
            }
        }
    }

    private func testConnection() {
        // The connection test happens automatically when databasePath is set
        // Just trigger a refresh by setting the same value
        databaseService.databasePath = tempDatabasePath
    }
}
