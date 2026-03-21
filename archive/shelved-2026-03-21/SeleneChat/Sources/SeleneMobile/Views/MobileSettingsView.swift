import SwiftUI

struct MobileSettingsView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var editURL = ""
    @State private var editToken = ""
    @State private var isReconnecting = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(connectionManager.isConnected ? "Connected" : "Disconnected")
                            .foregroundStyle(connectionManager.isConnected ? .green : .red)
                    }
                }

                Section("Server") {
                    TextField("Server URL", text: $editURL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        #endif
                    SecureField("API Token (optional)", text: $editToken)

                    Button(action: reconnect) {
                        if isReconnecting {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting...")
                            }
                        } else {
                            Text("Reconnect")
                        }
                    }
                    .disabled(editURL.isEmpty || isReconnecting)
                }

                if showError {
                    Section("Error") {
                        Text(connectionManager.lastError ?? "Could not connect. Check the URL and Tailscale.")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                editURL = connectionManager.serverURL
                editToken = connectionManager.apiToken
            }
        }
    }

    private func reconnect() {
        isReconnecting = true
        showError = false

        var url = editURL
        if !url.hasPrefix("http") {
            url = "http://\(url)"
        }

        Task {
            let success = await connectionManager.configure(serverURL: url, apiToken: editToken)
            isReconnecting = false
            showError = !success
        }
    }
}
