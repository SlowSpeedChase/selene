import SeleneShared
import Foundation

// MARK: - Data Models

struct ExtractedTask {
    let title: String
    let energy: String
    let minutes: Int
}

struct PlanningResponse {
    let message: String
    let extractedTasks: [ExtractedTask]
    let cleanMessage: String  // Message with task markers removed
}

// MARK: - Claude API Service

actor ClaudeAPIService {
    static let shared = ClaudeAPIService()

    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let session = URLSession.shared

    private var apiKey: String? {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }

    /// Synchronous check for API key availability (for UI)
    nonisolated var hasAPIKey: Bool {
        ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] != nil
    }

    private init() {}

    // MARK: - Error Types

    enum ClaudeError: Error, LocalizedError {
        case missingAPIKey
        case invalidResponse
        case requestFailed(Int, String)
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "ANTHROPIC_API_KEY environment variable not set"
            case .invalidResponse:
                return "Invalid response from Claude API"
            case .requestFailed(let status, let message):
                return "Claude API error (\(status)): \(message)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Public Methods

    /// Send a planning message to Claude API
    /// - Parameters:
    ///   - userMessage: The user's current message
    ///   - conversationHistory: Previous messages in the conversation
    ///   - systemPrompt: System prompt for the planning assistant
    /// - Returns: PlanningResponse containing message and extracted tasks
    func sendPlanningMessage(
        userMessage: String,
        conversationHistory: [[String: String]],
        systemPrompt: String
    ) async throws -> PlanningResponse {
        guard let apiKey = apiKey else {
            throw ClaudeError.missingAPIKey
        }

        let messages = buildMessages(
            userMessage: userMessage,
            conversationHistory: conversationHistory
        )

        let requestBody: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": messages
        ]

        guard let url = URL(string: baseURL) else {
            throw ClaudeError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60.0

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ClaudeError.requestFailed(httpResponse.statusCode, errorMessage)
            }

            // Parse response
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let firstContent = content.first,
                  let text = firstContent["text"] as? String else {
                throw ClaudeError.invalidResponse
            }

            let extractedTasks = extractTasks(from: text)
            let cleanMessage = removeTaskMarkers(from: text)

            return PlanningResponse(
                message: text,
                extractedTasks: extractedTasks,
                cleanMessage: cleanMessage
            )

        } catch let error as ClaudeError {
            throw error
        } catch {
            throw ClaudeError.networkError(error)
        }
    }

    /// Check if Claude API is available (API key is set)
    func isAvailable() async -> Bool {
        return apiKey != nil
    }

    // MARK: - Helper Methods

    /// Build messages array for Claude API request
    /// - Parameters:
    ///   - userMessage: The current user message to append
    ///   - conversationHistory: Previous conversation messages
    /// - Returns: Array of message dictionaries
    func buildMessages(
        userMessage: String,
        conversationHistory: [[String: String]]
    ) -> [[String: String]] {
        var messages = conversationHistory
        messages.append(["role": "user", "content": userMessage])
        return messages
    }

    /// Extract tasks from Claude's response using [TASK: ...] markers
    /// - Parameter response: The raw response text from Claude
    /// - Returns: Array of ExtractedTask objects
    func extractTasks(from response: String) -> [ExtractedTask] {
        var tasks: [ExtractedTask] = []

        // Pattern: [TASK: title | energy: low/medium/high | minutes: N]
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

    /// Remove task markers from response text for clean display
    /// - Parameter response: The raw response text with task markers
    /// - Returns: Clean text with task markers removed
    func removeTaskMarkers(from response: String) -> String {
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
