import Foundation

/// Extracts action items from LLM responses using structured markers
/// Format: [ACTION: description | ENERGY: level | TIMEFRAME: time]
public class ActionExtractor {

    // MARK: - Types

    public struct ExtractedAction: Equatable {
        public let description: String
        public let energy: EnergyLevel
        public let timeframe: Timeframe

        public init(description: String, energy: EnergyLevel, timeframe: Timeframe) {
            self.description = description
            self.energy = energy
            self.timeframe = timeframe
        }

        public enum EnergyLevel: String, Equatable {
            case high
            case medium
            case low
        }

        public enum Timeframe: String, Equatable {
            case today = "today"
            case thisWeek = "this-week"
            case someday = "someday"
        }
    }

    // MARK: - Private Properties

    /// Regex pattern to match action markers
    /// Format: [ACTION: description | ENERGY: level | TIMEFRAME: time]
    private let actionPattern = #"\[ACTION:\s*([^|]+)\s*\|\s*ENERGY:\s*(\w+)\s*\|\s*TIMEFRAME:\s*([^\]]+)\]"#

    // MARK: - Init

    public init() {}

    // MARK: - Public Methods

    /// Extract all action items from an LLM response
    /// - Parameter response: The LLM response string
    /// - Returns: Array of extracted actions
    public func extractActions(from response: String) -> [ExtractedAction] {
        guard let regex = try? NSRegularExpression(pattern: actionPattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(response.startIndex..., in: response)
        let matches = regex.matches(in: response, options: [], range: range)

        return matches.compactMap { match -> ExtractedAction? in
            guard match.numberOfRanges >= 4,
                  let descriptionRange = Range(match.range(at: 1), in: response),
                  let energyRange = Range(match.range(at: 2), in: response),
                  let timeframeRange = Range(match.range(at: 3), in: response) else {
                return nil
            }

            let description = String(response[descriptionRange]).trimmingCharacters(in: .whitespaces)
            let energyString = String(response[energyRange]).trimmingCharacters(in: .whitespaces).lowercased()
            let timeframeString = String(response[timeframeRange]).trimmingCharacters(in: .whitespaces).lowercased()

            // Parse energy with default fallback
            let energy = ExtractedAction.EnergyLevel(rawValue: energyString) ?? .medium

            // Parse timeframe with default fallback
            let timeframe = ExtractedAction.Timeframe(rawValue: timeframeString) ?? .someday

            return ExtractedAction(
                description: description,
                energy: energy,
                timeframe: timeframe
            )
        }
    }

    /// Remove action markers from a response for display
    /// - Parameter response: The LLM response string with action markers
    /// - Returns: Cleaned string without action markers
    public func removeActionMarkers(from response: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: actionPattern, options: .caseInsensitive) else {
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let range = NSRange(response.startIndex..., in: response)
        var result = regex.stringByReplacingMatches(in: response, options: [], range: range, withTemplate: "")

        // Clean up multiple consecutive newlines and whitespace
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
