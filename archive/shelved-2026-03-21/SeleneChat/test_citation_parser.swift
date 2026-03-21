#!/usr/bin/env swift

import Foundation

// Inline CitationParser for testing
struct ParsedCitation: Identifiable {
    let id = UUID()
    let noteTitle: String
    let noteDate: String
    let range: Range<String.Index>
    let displayText: String
}

class CitationParser {
    static func parse(_ text: String) -> (plainText: String, citations: [ParsedCitation]) {
        let pattern = #"\[Note: '([^']+)' - ([^\]]+)\]"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            print("CitationParser: Failed to create regex")
            return (text, [])
        }

        var citations: [ParsedCitation] = []
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let titleRange = match.range(at: 1)
            let dateRange = match.range(at: 2)
            let fullRange = match.range

            let title = nsString.substring(with: titleRange)
            let date = nsString.substring(with: dateRange)

            guard let swiftRange = Range(fullRange, in: text) else {
                print("CitationParser: Failed to convert range for citation: \(title)")
                continue
            }

            let citation = ParsedCitation(
                noteTitle: title,
                noteDate: date,
                range: swiftRange,
                displayText: "[\(title) - \(date)]"
            )

            citations.append(citation)
        }

        print("CitationParser: Found \(citations.count) citations in text")
        return (text, citations)
    }
}

// Test cases
func testParseSingleCitation() {
    print("\n=== Test: Parse Single Citation ===")
    let text = "Based on your notes [Note: 'Morning Routine' - Nov 14], I can see..."
    let (_, citations) = CitationParser.parse(text)

    assert(citations.count == 1, "Should find 1 citation")
    assert(citations[0].noteTitle == "Morning Routine", "Title should match")
    assert(citations[0].noteDate == "Nov 14", "Date should match")
    assert(citations[0].displayText == "[Morning Routine - Nov 14]", "Display text should match")
    print("✅ PASS: Single citation parsed correctly")
}

func testParseMultipleCitations() {
    print("\n=== Test: Parse Multiple Citations ===")
    let text = """
    Looking at [Note: 'Deep Work Session' - Nov 13] and [Note: 'Afternoon Slump' - Nov 14],
    I notice a pattern emerging.
    """
    let (_, citations) = CitationParser.parse(text)

    assert(citations.count == 2, "Should find 2 citations")
    assert(citations[0].noteTitle == "Deep Work Session", "First title should match")
    assert(citations[0].noteDate == "Nov 13", "First date should match")
    assert(citations[1].noteTitle == "Afternoon Slump", "Second title should match")
    assert(citations[1].noteDate == "Nov 14", "Second date should match")
    print("✅ PASS: Multiple citations parsed correctly")
}

func testNoCitations() {
    print("\n=== Test: No Citations ===")
    let text = "This is just plain text with no citations at all."
    let (_, citations) = CitationParser.parse(text)

    assert(citations.isEmpty, "Should find no citations")
    print("✅ PASS: No citations found as expected")
}

func testMalformedCitations() {
    print("\n=== Test: Malformed Citations ===")
    let text = """
    [Note: Missing closing quote - Nov 14]
    [Note: 'Missing date']
    [Note: 'Valid Citation' - Nov 15]
    """
    let (_, citations) = CitationParser.parse(text)

    assert(citations.count == 1, "Should only find 1 valid citation")
    assert(citations[0].noteTitle == "Valid Citation", "Should parse valid citation")
    print("✅ PASS: Malformed citations ignored correctly")
}

func testCitationWithSpecialCharacters() {
    print("\n=== Test: Citation with Special Characters ===")
    let text = "[Note: 'Project Planning: Q4 Roadmap (Draft #3)' - Nov 14, 2025]"
    let (_, citations) = CitationParser.parse(text)

    assert(citations.count == 1, "Should find 1 citation")
    assert(citations[0].noteTitle == "Project Planning: Q4 Roadmap (Draft #3)", "Should handle special characters")
    assert(citations[0].noteDate == "Nov 14, 2025", "Should handle date with year")
    print("✅ PASS: Special characters handled correctly")
}

func testCitationPositions() {
    print("\n=== Test: Citation Positions ===")
    let text = "Start [Note: 'First' - Nov 1] middle [Note: 'Second' - Nov 2] end"
    let (_, citations) = CitationParser.parse(text)

    assert(citations.count == 2, "Should find 2 citations")

    // Verify citations are in order
    assert(citations[0].range.lowerBound < citations[1].range.lowerBound, "Citations should be in position order")
    print("✅ PASS: Citation positions tracked correctly")
}

func testEmptyText() {
    print("\n=== Test: Empty Text ===")
    let text = ""
    let (_, citations) = CitationParser.parse(text)

    assert(citations.isEmpty, "Should find no citations in empty text")
    print("✅ PASS: Empty text handled correctly")
}

// Run all tests
print("╔══════════════════════════════════════════╗")
print("║  CitationParser Unit Tests               ║")
print("╚══════════════════════════════════════════╝")

var passedTests = 0
var totalTests = 7

let tests: [(String, () -> Void)] = [
    ("testParseSingleCitation", testParseSingleCitation),
    ("testParseMultipleCitations", testParseMultipleCitations),
    ("testNoCitations", testNoCitations),
    ("testMalformedCitations", testMalformedCitations),
    ("testCitationWithSpecialCharacters", testCitationWithSpecialCharacters),
    ("testCitationPositions", testCitationPositions),
    ("testEmptyText", testEmptyText)
]

for (name, test) in tests {
    do {
        test()
        passedTests += 1
    } catch {
        print("❌ FAIL: \(name) - \(error)")
    }
}

print("\n" + String(repeating: "═", count: 44))
print("Results: \(passedTests)/\(totalTests) tests passed")
if passedTests == totalTests {
    print("🎉 All tests passed!")
} else {
    print("⚠️  Some tests failed")
}
print(String(repeating: "═", count: 44) + "\n")
