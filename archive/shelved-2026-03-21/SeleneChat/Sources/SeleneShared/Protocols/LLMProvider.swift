import Foundation

/// Protocol abstracting LLM access for Selene.
/// Implemented by OllamaService (macOS, direct local) and RemoteLLMService (iOS, proxied via HTTP).
public protocol LLMProvider: AnyObject {

    /// Generate a text completion.
    /// - Parameters:
    ///   - prompt: The full prompt including system instructions and context.
    ///   - model: The model to use. Pass nil to use the provider's default.
    /// - Returns: Generated text response.
    func generate(prompt: String, model: String?) async throws -> String

    /// Generate an embedding vector for the given text.
    /// - Parameters:
    ///   - text: The text to embed.
    ///   - model: The embedding model to use. Pass nil to use the provider's default.
    /// - Returns: Embedding vector as an array of floats.
    func embed(text: String, model: String?) async throws -> [Float]

    /// Check whether the LLM service is available.
    func isAvailable() async -> Bool
}
