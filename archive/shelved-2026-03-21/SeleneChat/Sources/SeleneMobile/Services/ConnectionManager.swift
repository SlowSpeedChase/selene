import Foundation
import SeleneShared
import SwiftUI

@MainActor
class ConnectionManager: ObservableObject {
    @Published var serverURL: String = ""
    @Published var apiToken: String = ""
    @Published var isConnected = false
    @Published var isConfigured = false

    private(set) var dataProvider: RemoteDataService?
    private(set) var llmProvider: RemoteOllamaService?

    #if targetEnvironment(simulator)
    private static let defaultServerURL = "http://localhost:5678"
    #else
    private static let defaultServerURL = "http://100.111.6.10:5678"
    #endif

    init() {
        let savedURL = UserDefaults.standard.string(forKey: "selene_server_url") ?? Self.defaultServerURL
        let savedToken = UserDefaults.standard.string(forKey: "selene_api_token") ?? ""
        self.serverURL = savedURL
        self.apiToken = savedToken
        self.isConfigured = true
        Task {
            _ = await configure(serverURL: savedURL, apiToken: savedToken)
        }
    }

    @Published var lastError: String?

    func configure(serverURL: String, apiToken: String) async -> Bool {
        self.serverURL = serverURL
        self.apiToken = apiToken
        self.lastError = nil
        save()

        let remote = RemoteDataService(baseURL: serverURL, token: apiToken)
        let remoteLLM = RemoteOllamaService(baseURL: serverURL, token: apiToken)

        let available = await remote.isAPIAvailable()
        if available {
            self.dataProvider = remote
            self.llmProvider = remoteLLM
            self.isConnected = true
            self.isConfigured = true
            return true
        }
        self.lastError = await remote.connectionError()
        self.isConnected = false
        return false
    }

    private func save() {
        UserDefaults.standard.set(serverURL, forKey: "selene_server_url")
        UserDefaults.standard.set(apiToken, forKey: "selene_api_token")
    }
}
