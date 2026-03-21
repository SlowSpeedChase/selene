import SeleneShared
import XCTest
@testable import SeleneChat

final class OllamaServiceTests: XCTestCase {

    // MARK: - isAvailable() Tests

    func test_isAvailable_returnsTrue_whenOllamaRespondsWithModels() async {
        // Arrange
        let service = OllamaService.shared

        // Act
        let isAvailable = await service.isAvailable()

        // Assert
        // Note: This test requires Ollama to be running locally
        // In CI environments, this may return false - that's expected
        XCTAssertTrue(isAvailable, "Ollama should be available when it responds to /api/tags")
    }

    // MARK: - generate() Tests

    func test_generate_returnsResponse_whenOllamaAvailable() async throws {
        // Arrange
        let service = OllamaService.shared
        let prompt = "Say hello in one word"

        // Skip if Ollama not available
        guard await service.isAvailable() else {
            throw XCTSkip("Ollama service not running")
        }

        // Act
        let response = try await service.generate(prompt: prompt, model: "mistral:7b")

        // Assert
        XCTAssertFalse(response.isEmpty, "Response should not be empty")
        XCTAssertGreaterThan(response.count, 0, "Response should contain text")
    }

    func test_generate_usesDefaultModel_whenModelNotSpecified() async throws {
        // Arrange
        let service = OllamaService.shared
        let prompt = "Say hello"

        // Skip if Ollama not available
        guard await service.isAvailable() else {
            throw XCTSkip("Ollama service not running")
        }

        // Act
        let response = try await service.generate(prompt: prompt)

        // Assert
        XCTAssertFalse(response.isEmpty, "Should generate response with default model")
    }

    func test_generate_handlesLongPrompt() async throws {
        // Arrange
        let service = OllamaService.shared
        let longPrompt = String(repeating: "test ", count: 200) // ~1000 characters

        // Skip if Ollama not available
        guard await service.isAvailable() else {
            throw XCTSkip("Ollama service not running")
        }

        // Act
        let response = try await service.generate(prompt: longPrompt, model: "mistral:7b")

        // Assert
        XCTAssertFalse(response.isEmpty, "Should handle long prompts")
    }

    // MARK: - Timeout Tests

    func test_generate_completesWithinReasonableTime() async throws {
        // Arrange
        let service = OllamaService.shared
        let prompt = "Reply with one word"
        let startTime = Date()

        // Skip if Ollama not available
        guard await service.isAvailable() else {
            throw XCTSkip("Ollama service not running")
        }

        // Act
        _ = try await service.generate(prompt: prompt, model: "mistral:7b")
        let duration = Date().timeIntervalSince(startTime)

        // Assert
        XCTAssertLessThan(duration, 30.0, "Should complete within 30 seconds")
    }

    // MARK: - Edge Cases

    func test_generate_handlesEmptyPrompt() async throws {
        // Arrange
        let service = OllamaService.shared

        // Skip if Ollama not available
        guard await service.isAvailable() else {
            throw XCTSkip("Ollama service not running")
        }

        // Act & Assert
        do {
            _ = try await service.generate(prompt: "", model: "mistral:7b")
            // If it doesn't throw, that's fine - just shouldn't crash
        } catch {
            // Also acceptable to throw error for empty prompt
            XCTAssertNotNil(error)
        }
    }

    func test_generate_handlesSpecialCharacters() async throws {
        // Arrange
        let service = OllamaService.shared
        let prompt = "What is 2+2? Answer: \"four\" & 'quatre'"

        // Skip if Ollama not available
        guard await service.isAvailable() else {
            throw XCTSkip("Ollama service not running")
        }

        // Act
        let response = try await service.generate(prompt: prompt, model: "mistral:7b")

        // Assert
        XCTAssertFalse(response.isEmpty, "Should handle special characters in prompt")
    }
}
