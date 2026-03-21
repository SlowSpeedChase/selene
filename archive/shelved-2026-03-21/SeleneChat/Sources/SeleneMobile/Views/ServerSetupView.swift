import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var connectionManager: ConnectionManager
    @State private var serverURL = ""
    @State private var apiToken = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection") {
                    TextField("Tailscale IP:Port", text: $serverURL)
                        .textContentType(.URL)
                    #if os(iOS)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    #endif
                    SecureField("API Token", text: $apiToken)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: connect) {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(serverURL.isEmpty || isConnecting)
                }
            }
            .navigationTitle("Selene Setup")
        }
    }

    private func connect() {
        isConnecting = true
        errorMessage = nil

        var url = serverURL
        if !url.hasPrefix("http") {
            url = "http://\(url)"
        }

        Task {
            let success = await connectionManager.configure(serverURL: url, apiToken: apiToken)
            isConnecting = false
            if !success {
                errorMessage = "Could not connect to server. Check the URL and make sure Tailscale is active."
            }
        }
    }
}
