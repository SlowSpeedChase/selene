import Foundation

/// Routes LLM tasks to the best provider based on task type.
/// Defaults are research-backed: Apple for classification/labeling, Ollama for conversation/reasoning.
public class LLMRouter {

    /// Task types that can be routed to different providers.
    public enum TaskType: String, CaseIterable {
        case chunkLabeling
        case embedding
        case queryAnalysis
        case summarization
        case threadChat
        case briefing
        case deepDive
    }

    public enum ProviderPreference: String {
        case apple
        case ollama
    }

    private let ollamaProvider: LLMProvider
    private let appleProvider: LLMProvider?

    private let defaults: [TaskType: ProviderPreference] = [
        .chunkLabeling: .apple,
        .embedding: .ollama,
        .queryAnalysis: .apple,
        .summarization: .apple,
        .threadChat: .ollama,
        .briefing: .ollama,
        .deepDive: .ollama,
    ]

    public init(ollamaProvider: LLMProvider, appleProvider: LLMProvider?) {
        self.ollamaProvider = ollamaProvider
        self.appleProvider = appleProvider
    }

    /// Get the provider for a given task type.
    /// Falls back to Ollama if Apple provider is unavailable.
    public func provider(for task: TaskType) -> LLMProvider {
        let preference = defaults[task] ?? .ollama
        switch preference {
        case .apple:
            return appleProvider ?? ollamaProvider
        case .ollama:
            return ollamaProvider
        }
    }

    /// Get the embedding provider. Always Ollama (nomic-embed-text).
    public func embeddingProvider() -> LLMProvider {
        return ollamaProvider
    }
}
