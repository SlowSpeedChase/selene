import Foundation

/// Splits note content into idea-level chunks for semantic retrieval.
/// Uses rule-based splitting (paragraphs, headers, sentence boundaries).
public class ChunkingService {

    private let minTokens = 100
    private let maxTokens = 256

    public init() {}

    /// Estimate token count using 4-chars-per-token heuristic.
    public func estimateTokens(_ text: String) -> Int {
        text.count / 4
    }

    /// Split note content into chunks of approximately 100-256 tokens each.
    public func splitIntoChunks(_ content: String) -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var rawSegments = splitOnBoundaries(trimmed)

        rawSegments = rawSegments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawSegments.isEmpty else { return [] }

        var splitSegments: [String] = []
        for segment in rawSegments {
            if estimateTokens(segment) > maxTokens {
                splitSegments.append(contentsOf: splitAtSentences(segment))
            } else {
                splitSegments.append(segment)
            }
        }

        return mergeSmallSegments(splitSegments)
    }

    // MARK: - Private

    private func splitOnBoundaries(_ text: String) -> [String] {
        let pattern = #"\n\s*\n|(?=^#{1,6}\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return [text]
        }

        var segments: [String] = []
        var lastEnd = text.startIndex

        let nsRange = NSRange(text.startIndex..., in: text)
        regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
            guard let matchRange = match.flatMap({ Range($0.range, in: text) }) else { return }
            let segment = String(text[lastEnd..<matchRange.lowerBound])
            if !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(segment)
            }
            lastEnd = matchRange.upperBound
        }

        let remaining = String(text[lastEnd...])
        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(remaining)
        }

        return segments.isEmpty ? [text] : segments
    }

    private func splitAtSentences(_ text: String) -> [String] {
        let sentences = text.components(separatedBy: .init(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            let withSentence = current.isEmpty ? sentence + "." : current + " " + sentence + "."
            if estimateTokens(withSentence) > maxTokens && !current.isEmpty {
                chunks.append(current)
                current = sentence + "."
            } else {
                current = withSentence
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private func mergeSmallSegments(_ segments: [String]) -> [String] {
        var merged: [String] = []
        var current = ""

        for segment in segments {
            if current.isEmpty {
                current = segment
                continue
            }

            let combined = current + "\n\n" + segment
            if estimateTokens(combined) <= maxTokens {
                current = combined
            } else {
                merged.append(current)
                current = segment
            }
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            merged.append(current)
        }

        return merged
    }
}
