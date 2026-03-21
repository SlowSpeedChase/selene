import Foundation
import SeleneShared

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple Intelligence LLM provider using on-device Foundation Models.
/// Falls back gracefully on systems without Apple Intelligence.
@available(macOS 26, *)
class AppleIntelligenceService: LLMProvider {

    init() {}

    func generate(prompt: String, model: String?) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw AppleIntelligenceError.notAvailable
        #endif
    }

    func embed(text: String, model: String?) async throws -> [Float] {
        // Apple NLContextualEmbedding would go here.
        // For now, embedding is routed to Ollama via LLMRouter.
        throw AppleIntelligenceError.embeddingNotSupported
    }

    func isAvailable() async -> Bool {
        #if canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// Generate a concise topic label for a chunk of text.
    /// Uses the contentTagging model variant for optimal classification.
    func labelTopic(chunk: String) async throws -> String {
        #if canImport(FoundationModels)
        let session = LanguageModelSession(model: SystemLanguageModel(useCase: .contentTagging))
        let prompt = "Generate a 5-10 word topic label for this text. Return ONLY the label, nothing else.\n\nText: \(chunk)"
        let response = try await session.respond(to: prompt)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw AppleIntelligenceError.notAvailable
        #endif
    }

    enum AppleIntelligenceError: Error, LocalizedError {
        case notAvailable
        case embeddingNotSupported

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Apple Intelligence is not available on this system"
            case .embeddingNotSupported:
                return "Use Ollama nomic-embed-text for embeddings instead"
            }
        }
    }
}
