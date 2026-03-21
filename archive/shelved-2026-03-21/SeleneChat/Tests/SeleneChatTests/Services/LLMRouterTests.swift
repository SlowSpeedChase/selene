import SeleneShared
import XCTest
@testable import SeleneChat

final class LLMRouterTests: XCTestCase {

    // MARK: - Mock Provider

    private class MockLLMProvider: LLMProvider {
        let name: String
        init(name: String) { self.name = name }
        func generate(prompt: String, model: String?) async throws -> String { "mock" }
        func embed(text: String, model: String?) async throws -> [Float] { [] }
        func isAvailable() async -> Bool { true }
    }

    // MARK: - Ollama Defaults

    func testDefaultsOllamaForThreadChat() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)
        let provider = router.provider(for: .threadChat)
        XCTAssertTrue(provider === ollama)
    }

    func testDefaultsOllamaForBriefing() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)
        let provider = router.provider(for: .briefing)
        XCTAssertTrue(provider === ollama)
    }

    func testDefaultsOllamaForDeepDive() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)
        let provider = router.provider(for: .deepDive)
        XCTAssertTrue(provider === ollama)
    }

    // MARK: - Apple Defaults

    func testDefaultsAppleForChunkLabeling() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)
        let provider = router.provider(for: .chunkLabeling)
        XCTAssertTrue(provider === apple)
    }

    func testDefaultsAppleForSummarization() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)
        let provider = router.provider(for: .summarization)
        XCTAssertTrue(provider === apple)
    }

    func testDefaultsAppleForQueryAnalysis() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)
        let provider = router.provider(for: .queryAnalysis)
        XCTAssertTrue(provider === apple)
    }

    // MARK: - Fallback

    func testFallsBackToOllamaWhenAppleUnavailable() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)
        let provider = router.provider(for: .chunkLabeling)
        XCTAssertTrue(provider === ollama)
    }

    // MARK: - Embedding

    func testEmbeddingProviderAlwaysReturnsOllama() {
        let ollama = MockLLMProvider(name: "ollama")
        let apple = MockLLMProvider(name: "apple")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: apple)
        let provider = router.embeddingProvider()
        XCTAssertTrue(provider === ollama)
    }

    // MARK: - All Task Types

    func testAllTaskTypesReturnAProvider() {
        let ollama = MockLLMProvider(name: "ollama")
        let router = LLMRouter(ollamaProvider: ollama, appleProvider: nil)
        for taskType in LLMRouter.TaskType.allCases {
            let provider = router.provider(for: taskType)
            XCTAssertNotNil(provider)
        }
    }
}
