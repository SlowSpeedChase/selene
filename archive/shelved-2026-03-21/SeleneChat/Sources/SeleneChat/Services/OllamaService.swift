import SeleneShared
import Foundation

// MARK: - Request/Response Models

private struct GenerateOptions: Codable {
    let num_ctx: Int?
}

private struct GenerateRequest: Codable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: GenerateOptions?
}

private struct GenerateResponse: Codable {
    let model: String
    let response: String
    let done: Bool
}

private struct EmbedRequest: Codable {
    let model: String
    let prompt: String
}

private struct EmbedResponse: Codable {
    let embedding: [Float]
}

actor OllamaService {
    static let shared = OllamaService()

    private let baseURL = "http://localhost:11434"
    private let session = URLSession.shared

    private var lastAvailabilityCheck: Date?
    private var cachedAvailability: Bool = false
    private let cacheTimeout: TimeInterval = 60  // Cache for 60 seconds

    private init() {}

    enum OllamaError: Error, LocalizedError {
        case serviceUnavailable
        case invalidResponse
        case decodingError
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .serviceUnavailable:
                return "Ollama service is not running at localhost:11434"
            case .invalidResponse:
                return "Invalid response from Ollama service"
            case .decodingError:
                return "Failed to decode response from Ollama"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }

    /// Check if Ollama service is running and available (cached for 60s)
    func isAvailable() async -> Bool {
        // Return cached result if fresh
        if let lastCheck = lastAvailabilityCheck,
           Date().timeIntervalSince(lastCheck) < cacheTimeout {
            return cachedAvailability
        }

        // Perform actual health check
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return false
        }

        do {
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                #if DEBUG
                DebugLogger.shared.log(.state, "OllamaService.isAvailable: false (status \(statusCode))")
                #endif
                cachedAvailability = false
                lastAvailabilityCheck = Date()
                return false
            }

            // Try to decode response to verify it's valid JSON
            _ = try JSONSerialization.jsonObject(with: data)

            cachedAvailability = true
            lastAvailabilityCheck = Date()
            return true

        } catch {
            print("⚠️ Ollama health check failed: \(error.localizedDescription)")
            cachedAvailability = false
            lastAvailabilityCheck = Date()
            return false
        }
    }

    /// Generate text completion from Ollama (LLMProvider conformance)
    func generate(prompt: String, model: String? = nil) async throws -> String {
        try await generate(prompt: prompt, model: model, numCtx: nil)
    }

    /// Generate text completion from Ollama with optional context window size
    /// - Parameters:
    ///   - prompt: The full prompt including system instructions and context
    ///   - model: The model to use (default: mistral:7b)
    ///   - numCtx: Optional context window size (e.g. 16384 for thread chat)
    /// - Returns: Generated text response
    func generate(prompt: String, model: String? = nil, numCtx: Int?) async throws -> String {
        let resolvedModel = model ?? "mistral:7b"

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidResponse
        }

        // Build request body
        let options = numCtx.map { GenerateOptions(num_ctx: $0) }
        let requestBody = GenerateRequest(
            model: resolvedModel,
            prompt: prompt,
            stream: false,
            options: options
        )

        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 120.0  // 120 second timeout (large prompts with context can take time)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                print("⚠️ Ollama returned status \(httpResponse.statusCode)")
                throw OllamaError.serviceUnavailable
            }

            // Decode response
            let generateResponse = try JSONDecoder().decode(GenerateResponse.self, from: data)

            #if DEBUG
            DebugLogger.shared.log(.state, "OllamaService.generate: success, response length=\(generateResponse.response.count)")
            #endif

            return generateResponse.response

        } catch let error as OllamaError {
            #if DEBUG
            DebugLogger.shared.log(.error, "OllamaService.generate|\(error.localizedDescription)")
            #endif
            throw error
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "OllamaService.generate|network error: \(error.localizedDescription)")
            #endif
            print("⚠️ Ollama generate error: \(error.localizedDescription)")
            throw OllamaError.networkError(error)
        }
    }

    /// Generate embedding vector for text
    /// - Parameters:
    ///   - text: The text to embed
    ///   - model: The embedding model to use (default: nomic-embed-text)
    /// - Returns: Embedding vector as array of floats
    func embed(text: String, model: String? = nil) async throws -> [Float] {
        let resolvedModel = model ?? "nomic-embed-text"

        guard let url = URL(string: "\(baseURL)/api/embeddings") else {
            throw OllamaError.invalidResponse
        }

        // Build request body
        let requestBody = EmbedRequest(
            model: resolvedModel,
            prompt: text
        )

        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30.0  // 30 second timeout

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                print("⚠️ Ollama returned status \(httpResponse.statusCode)")
                throw OllamaError.serviceUnavailable
            }

            // Decode response
            let embedResponse = try JSONDecoder().decode(EmbedResponse.self, from: data)

            #if DEBUG
            DebugLogger.shared.log(.state, "OllamaService.embed: success, embedding dimensions=\(embedResponse.embedding.count)")
            #endif

            return embedResponse.embedding

        } catch let error as OllamaError {
            #if DEBUG
            DebugLogger.shared.log(.error, "OllamaService.embed|\(error.localizedDescription)")
            #endif
            throw error
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "OllamaService.embed|network error: \(error.localizedDescription)")
            #endif
            print("⚠️ Ollama embed error: \(error.localizedDescription)")
            throw OllamaError.networkError(error)
        }
    }
}

extension OllamaService: LLMProvider {}
