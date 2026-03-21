#!/usr/bin/env swift
import Foundation

// Simple test runner to verify OllamaService behavior
// Run with: swift test_ollama.swift

print("🧪 Testing OllamaService")
print(String(repeating: "=", count: 60))

// We'll verify the tests fail by checking if Ollama responds
// This simulates what our tests will do

func testOllamaAvailability() async {
    print("\n📍 Test: Check if Ollama is available")

    let url = URL(string: "http://localhost:11434/api/tags")!
    var request = URLRequest(url: url)
    request.timeoutInterval = 5.0

    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            print("✅ Ollama is running and available")
        } else {
            print("❌ Ollama returned unexpected status")
        }
    } catch {
        print("❌ Ollama is not available: \(error.localizedDescription)")
    }
}

func testOllamaGenerate() async {
    print("\n📍 Test: Generate text with Ollama")

    let url = URL(string: "http://localhost:11434/api/generate")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 30.0

    let payload: [String: Any] = [
        "model": "mistral:7b",
        "prompt": "Say hello in one word",
        "stream": false
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let responseText = json["response"] as? String {
                print("✅ Generated response: \"\(responseText.prefix(50))...\"")
            } else {
                print("❌ Could not parse response")
            }
        } else {
            print("❌ Generate returned unexpected status")
        }
    } catch {
        print("❌ Generate failed: \(error.localizedDescription)")
    }
}

// Run tests
Task {
    await testOllamaAvailability()
    await testOllamaGenerate()

    print("\n" + String(repeating: "=", count: 60))
    print("✨ Test run complete\n")
    exit(0)
}

// Keep script running
RunLoop.main.run()
