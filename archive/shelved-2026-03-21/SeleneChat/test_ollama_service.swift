#!/usr/bin/env swift
import Foundation

// Inline OllamaService for testing
class OllamaService {
    private let baseURL: String
    private let defaultModel: String
    private let session: URLSession

    init(baseURL: String = "http://localhost:11434", defaultModel: String = "mistral:7b") {
        self.baseURL = baseURL
        self.defaultModel = defaultModel

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        self.session = URLSession(configuration: config)
    }

    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0

        do {
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    func generate(prompt: String, model: String? = nil) async throws -> String {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OllamaError.emptyPrompt
        }

        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw OllamaError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60.0

        let modelToUse = model ?? defaultModel
        let payload: [String: Any] = [
            "model": modelToUse,
            "prompt": prompt,
            "stream": false,
            "options": [
                "temperature": 0.3
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OllamaError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw OllamaError.connectionFailed
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseText = json["response"] as? String else {
                throw OllamaError.invalidResponse
            }

            return responseText

        } catch let error as OllamaError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorTimedOut {
                throw OllamaError.timeout
            }
            throw OllamaError.connectionFailed
        }
    }
}

enum OllamaError: Error, LocalizedError {
    case connectionFailed
    case invalidResponse
    case timeout
    case emptyPrompt
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Failed to connect to Ollama service"
        case .invalidResponse:
            return "Invalid response from Ollama"
        case .timeout:
            return "Request timed out"
        case .emptyPrompt:
            return "Prompt cannot be empty"
        case .invalidURL:
            return "Invalid Ollama URL"
        }
    }
}

// Test runner
print("🧪 Testing OllamaService Implementation")
print(String(repeating: "=", count: 60))

var passedTests = 0
var failedTests = 0

func assert(_ condition: Bool, _ message: String) {
    if condition {
        print("✅ PASS: \(message)")
        passedTests += 1
    } else {
        print("❌ FAIL: \(message)")
        failedTests += 1
    }
}

Task {
    let service = OllamaService()

    // Test 1: isAvailable returns true when Ollama running
    print("\n📍 Test 1: isAvailable() returns true when Ollama is running")
    let isAvailable = await service.isAvailable()
    assert(isAvailable, "Ollama should be available")

    // Test 2: isAvailable returns false with bad URL
    print("\n📍 Test 2: isAvailable() returns false with invalid port")
    let badService = OllamaService(baseURL: "http://localhost:99999")
    let isBadAvailable = await badService.isAvailable()
    assert(!isBadAvailable, "Should return false for unavailable service")

    // Test 3: generate() returns response
    print("\n📍 Test 3: generate() returns valid response")
    do {
        let startTime = Date()
        let response = try await service.generate(prompt: "Say hello in one word")
        let duration = Date().timeIntervalSince(startTime)

        assert(!response.isEmpty, "Response should not be empty")
        assert(response.count > 0, "Response should contain text")
        print("   Response: \"\(response.prefix(50))...\"")
        print("   Duration: \(String(format: "%.2f", duration))s")

    } catch {
        assert(false, "generate() should not throw: \(error)")
    }

    // Test 4: generate() uses default model
    print("\n📍 Test 4: generate() uses default model when not specified")
    do {
        let response = try await service.generate(prompt: "Say hi")
        assert(!response.isEmpty, "Should generate with default model")
    } catch {
        assert(false, "Should work with default model: \(error)")
    }

    // Test 5: generate() throws on empty prompt
    print("\n📍 Test 5: generate() throws error for empty prompt")
    do {
        _ = try await service.generate(prompt: "")
        assert(false, "Should throw error for empty prompt")
    } catch OllamaError.emptyPrompt {
        assert(true, "Correctly throws emptyPrompt error")
    } catch {
        assert(false, "Wrong error type: \(error)")
    }

    // Test 6: generate() handles long prompts
    print("\n📍 Test 6: generate() handles long prompts")
    do {
        let longPrompt = String(repeating: "test ", count: 200)
        let response = try await service.generate(prompt: longPrompt)
        assert(!response.isEmpty, "Should handle long prompts")
    } catch {
        assert(false, "Should handle long prompts: \(error)")
    }

    // Test 7: generate() throws when Ollama not running
    print("\n📍 Test 7: generate() throws when Ollama unavailable")
    do {
        _ = try await badService.generate(prompt: "test")
        assert(false, "Should throw when service unavailable")
    } catch OllamaError.connectionFailed {
        assert(true, "Correctly throws connectionFailed error")
    } catch {
        assert(true, "Throws error for unavailable service: \(error)")
    }

    // Test 8: Performance - completes within reasonable time
    print("\n📍 Test 8: generate() completes within 30 seconds")
    do {
        let startTime = Date()
        _ = try await service.generate(prompt: "Reply with one word")
        let duration = Date().timeIntervalSince(startTime)
        assert(duration < 30.0, "Should complete within 30 seconds (took \(String(format: "%.2f", duration))s)")
    } catch {
        assert(false, "Performance test failed: \(error)")
    }

    // Summary
    print("\n" + String(repeating: "=", count: 60))
    print("📊 Test Results:")
    print("   ✅ Passed: \(passedTests)")
    print("   ❌ Failed: \(failedTests)")
    print("   Total: \(passedTests + failedTests)")

    if failedTests == 0 {
        print("\n🎉 All tests passed!")
    } else {
        print("\n⚠️  Some tests failed")
    }

    print(String(repeating: "=", count: 60) + "\n")
    exit(failedTests == 0 ? 0 : 1)
}

RunLoop.main.run()
