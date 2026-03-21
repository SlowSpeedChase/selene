import Foundation
import SwiftUI

/// Parses Ollama responses for note citations and creates attributed strings with tappable links
public class CitationParser {

    // MARK: - Types

    public struct ParsedCitation: Identifiable {
        public let id = UUID()
        public let noteTitle: String
        public let noteDate: String
        public let range: Range<String.Index>

        /// Original citation text like "[Note: 'Title' - Date]"
        public var fullText: String {
            "[Note: '\(noteTitle)' - \(noteDate)]"
        }

        public init(noteTitle: String, noteDate: String, range: Range<String.Index>) {
            self.noteTitle = noteTitle
            self.noteDate = noteDate
            self.range = range
        }
    }

    public struct ParseResult {
        public let attributedText: AttributedString
        public let citations: [ParsedCitation]

        public init(attributedText: AttributedString, citations: [ParsedCitation]) {
            self.attributedText = attributedText
            self.citations = citations
        }
    }

    // MARK: - Init

    public init() {}

    // MARK: - Parsing

    /// Parse citations from Ollama response text
    /// Pattern: [Note: 'Title' - Date]
    public static func parse(_ text: String) -> ParseResult {
        // Regex pattern to match: [Note: 'Title' - Date]
        let pattern = #"\[Note: '([^']+)' - ([^\]]+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            // If regex fails, return plain text
            return ParseResult(
                attributedText: AttributedString(text),
                citations: []
            )
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        var citations: [ParsedCitation] = []

        // Extract citations
        for match in matches {
            guard match.numberOfRanges == 3 else { continue }

            let titleRange = match.range(at: 1)
            let dateRange = match.range(at: 2)
            let fullRange = match.range(at: 0)

            guard let titleSwiftRange = Range(titleRange, in: text),
                  let dateSwiftRange = Range(dateRange, in: text),
                  let fullSwiftRange = Range(fullRange, in: text) else {
                continue
            }

            let title = String(text[titleSwiftRange])
            let date = String(text[dateSwiftRange])

            let citation = ParsedCitation(
                noteTitle: title,
                noteDate: date,
                range: fullSwiftRange
            )

            citations.append(citation)
        }

        // Build attributed string with clickable citations
        var attributed = AttributedString(text)

        // Apply styling to citations (in reverse order to preserve ranges)
        for citation in citations.reversed() {
            if let attrRange = Range(citation.range, in: attributed) {
                // Make citation blue and underlined
                attributed[attrRange].foregroundColor = .blue
                attributed[attrRange].underlineStyle = .single

                // Add link for tapping
                // We'll use a custom URL scheme: selene-note://title/date
                let encodedTitle = citation.noteTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? citation.noteTitle
                let encodedDate = citation.noteDate.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? citation.noteDate
                if let url = URL(string: "selene-note://\(encodedTitle)/\(encodedDate)") {
                    attributed[attrRange].link = url
                }
            }
        }

        return ParseResult(
            attributedText: attributed,
            citations: citations
        )
    }

    // MARK: - Citation Matching

    /// Find the note that matches a citation from the provided note list
    public static func findNote(for citation: ParsedCitation, in notes: [Note]) -> Note? {
        // Try exact title match first
        if let exactMatch = notes.first(where: { $0.title == citation.noteTitle }) {
            return exactMatch
        }

        // Try case-insensitive title match
        let lowercaseTitle = citation.noteTitle.lowercased()
        if let caseInsensitiveMatch = notes.first(where: { $0.title.lowercased() == lowercaseTitle }) {
            return caseInsensitiveMatch
        }

        // Try partial title match (contains)
        if let partialMatch = notes.first(where: { $0.title.lowercased().contains(lowercaseTitle) }) {
            return partialMatch
        }

        // Try matching by date if title doesn't work
        // Parse the date from citation (e.g., "Nov 14", "Nov 14, 2025", "2025-11-14")
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd"

        if let citationDate = dateFormatter.date(from: citation.noteDate) {
            // Find notes created on the same day
            let calendar = Calendar.current
            let matchingNotes = notes.filter { note in
                calendar.isDate(note.createdAt, equalTo: citationDate, toGranularity: .day)
            }

            // If we found notes on that date, try to match title
            if let match = matchingNotes.first(where: { $0.title.lowercased().contains(lowercaseTitle) }) {
                return match
            }

            // Return first note from that date if title still doesn't match
            return matchingNotes.first
        }

        return nil
    }

    /// Extract citation info from a selene-note:// URL
    public static func extractCitation(from url: URL) -> ParsedCitation? {
        guard url.scheme == "selene-note" else { return nil }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2 else { return nil }

        let title = pathComponents[0].removingPercentEncoding ?? pathComponents[0]
        let date = pathComponents[1].removingPercentEncoding ?? pathComponents[1]

        // Create a dummy range (we don't need the actual range for URL-based citations)
        let dummyRange = title.startIndex..<title.endIndex

        return ParsedCitation(
            noteTitle: title,
            noteDate: date,
            range: dummyRange
        )
    }
}
