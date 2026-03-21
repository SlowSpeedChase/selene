import Foundation
import SeleneShared

actor RemoteOllamaService: LLMProvider {
    let baseURL: String
    let token: String
    private let session: URLSession

    init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        self.session = URLSession(configuration: config)
    }

    func generate(prompt: String, model: String?) async throws -> String {
        struct Body: Encodable { let prompt: String; let model: String? }
        struct Response: Decodable { let response: String }

        guard let url = URL(string: "\(baseURL)/api/llm/generate") else {
            throw RemoteServiceError.invalidURL("/api/llm/generate")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Body(prompt: prompt, model: model))
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(Response.self, from: data).response
    }

    func embed(text: String, model: String?) async throws -> [Float] {
        struct Body: Encodable { let text: String; let model: String? }
        struct Response: Decodable { let embedding: [Float] }

        guard let url = URL(string: "\(baseURL)/api/llm/embed") else {
            throw RemoteServiceError.invalidURL("/api/llm/embed")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Body(text: text, model: model))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw RemoteServiceError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(Response.self, from: data).embedding
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/llm/health") else { return false }
        var request = URLRequest(url: url)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            struct Response: Decodable { let available: Bool }
            let (data, _) = try await session.data(for: request)
            return (try? JSONDecoder().decode(Response.self, from: data).available) ?? false
        } catch {
            return false
        }
    }
}
