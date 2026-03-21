import SeleneShared
// SeleneChat/Sources/Services/AIProviderService.swift
import Foundation
import SwiftUI

class AIProviderService: ObservableObject {
    static let shared = AIProviderService()

    private let userDefaultsKey = "defaultAIProvider"

    @Published var globalDefault: AIProvider {
        didSet {
            UserDefaults.standard.set(globalDefault.rawValue, forKey: userDefaultsKey)
        }
    }

    private let ollamaService = OllamaService.shared
    private let claudeService = ClaudeAPIService.shared

    private init() {
        // Load saved preference or default to local
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let provider = AIProvider(rawValue: saved) {
            self.globalDefault = provider
        } else {
            self.globalDefault = .local
        }
    }

    // MARK: - Availability Checks

    func isCloudAvailable() async -> Bool {
        await claudeService.isAvailable()
    }

    func isLocalAvailable() async -> Bool {
        await ollamaService.isAvailable()
    }

    // MARK: - Planning Messages

    /// Send a planning message using the specified provider
    func sendPlanningMessage(
        userMessage: String,
        conversationHistory: [[String: String]],
        systemPrompt: String,
        provider: AIProvider
    ) async throws -> PlanningResponse {
        switch provider {
        case .cloud:
            return try await claudeService.sendPlanningMessage(
                userMessage: userMessage,
                conversationHistory: conversationHistory,
                systemPrompt: systemPrompt
            )
        case .local:
            return try await sendLocalPlanningMessage(
                userMessage: userMessage,
                conversationHistory: conversationHistory,
                systemPrompt: systemPrompt
            )
        }
    }

    /// Convert Ollama response to PlanningResponse format
    private func sendLocalPlanningMessage(
        userMessage: String,
        conversationHistory: [[String: String]],
        systemPrompt: String
    ) async throws -> PlanningResponse {
        // Build prompt with context
        var fullPrompt = systemPrompt + "\n\n"

        for message in conversationHistory {
            if let role = message["role"], let content = message["content"] {
                fullPrompt += "\(role.capitalized): \(content)\n\n"
            }
        }

        fullPrompt += "User: \(userMessage)\n\nAssistant:"

        let response = try await ollamaService.generate(prompt: fullPrompt)

        // Extract tasks using same pattern as ClaudeAPIService
        let extractedTasks = extractTasks(from: response)
        let cleanMessage = removeTaskMarkers(from: response)

        return PlanningResponse(
            message: response,
            extractedTasks: extractedTasks,
            cleanMessage: cleanMessage
        )
    }

    /// Extract tasks from response using [TASK: ...] markers
    private func extractTasks(from response: String) -> [ExtractedTask] {
        var tasks: [ExtractedTask] = []
        let pattern = #"\[TASK:\s*([^|]+)\s*\|\s*energy:\s*(low|medium|high)\s*\|\s*minutes:\s*(\d+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return tasks
        }

        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, options: [], range: range)

        for match in matches {
            if let titleRange = Range(match.range(at: 1), in: response),
               let energyRange = Range(match.range(at: 2), in: response),
               let minutesRange = Range(match.range(at: 3), in: response) {

                let title = String(response[titleRange]).trimmingCharacters(in: .whitespaces)
                let energy = String(response[energyRange]).lowercased()
                let minutes = Int(response[minutesRange]) ?? 30

                tasks.append(ExtractedTask(title: title, energy: energy, minutes: minutes))
            }
        }

        return tasks
    }

    /// Remove task markers from response
    private func removeTaskMarkers(from response: String) -> String {
        let pattern = #"\[TASK:[^\]]+\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return response
        }

        let range = NSRange(response.startIndex..., in: response)
        return regex.stringByReplacingMatches(
            in: response,
            options: [],
            range: range,
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
