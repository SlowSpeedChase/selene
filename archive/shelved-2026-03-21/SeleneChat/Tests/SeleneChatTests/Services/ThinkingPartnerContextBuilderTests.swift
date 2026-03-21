import SeleneShared
import XCTest
@testable import SeleneChat

final class ThinkingPartnerContextBuilderTests: XCTestCase {

    func testFormatThreadForContext() {
        let thread = Thread(
            id: 1,
            name: "Event-Driven Architecture",
            why: "Exploring testing strategies",
            summary: "Notes about event testing approaches",
            status: "active",
            noteCount: 5,
            momentumScore: 0.8,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        let builder = ThinkingPartnerContextBuilder()
        let formatted = builder.formatThread(thread)

        XCTAssertTrue(formatted.contains("Event-Driven Architecture"))
        XCTAssertTrue(formatted.contains("active"))
        XCTAssertTrue(formatted.contains("5 notes"))
        XCTAssertTrue(formatted.contains("0.8"))
    }

    func testEstimateTokens() {
        let builder = ThinkingPartnerContextBuilder()
        let text = "Hello world this is a test"  // 26 chars
        let tokens = builder.estimateTokens(text)

        XCTAssertEqual(tokens, 6)  // 26 / 4 = 6
    }

    func testTruncateToFit() {
        let builder = ThinkingPartnerContextBuilder()
        let longText = String(repeating: "a", count: 100)  // 100 chars = 25 tokens

        let truncated = builder.truncateToFit(longText, maxTokens: 10)  // 10 tokens = 40 chars
        // 40 chars + "\n[Truncated for token limit]" (28 chars) = 68 chars max
        XCTAssertLessThanOrEqual(truncated.count, 70)
        XCTAssertTrue(truncated.contains("[Truncated for token limit]"))
    }

    // MARK: - Briefing Context Tests

    func testBuildBriefingContext() {
        let threads = [
            Thread(
                id: 1,
                name: "Event-Driven Architecture",
                why: "Testing strategies",
                summary: "Exploring event testing",
                status: "active",
                noteCount: 5,
                momentumScore: 0.8,
                lastActivityAt: Date(),
                createdAt: Date()
            ),
            Thread(
                id: 2,
                name: "Project Journey",
                why: nil,
                summary: "Early exploration",
                status: "active",
                noteCount: 3,
                momentumScore: 0.4,
                lastActivityAt: Date().addingTimeInterval(-86400 * 3),
                createdAt: Date()
            )
        ]

        let recentNotes = [
            Note(
                id: 1,
                title: "Testing thoughts",
                content: "Some content about testing",
                contentHash: "abc123",
                sourceType: "drafts",
                wordCount: 5,
                characterCount: 27,
                tags: nil,
                createdAt: Date(),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            )
        ]

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildBriefingContext(threads: threads, recentNotes: recentNotes)

        // Should include threads
        XCTAssertTrue(context.contains("Event-Driven Architecture"))
        XCTAssertTrue(context.contains("Project Journey"))

        // Should include momentum
        XCTAssertTrue(context.contains("Momentum"))

        // Should include recent notes section
        XCTAssertTrue(context.contains("Recent Notes"))
        XCTAssertTrue(context.contains("Testing thoughts"))
    }

    func testBriefingContextRespectsTokenBudget() {
        // Create many threads to exceed budget
        var threads: [SeleneChat.Thread] = []
        for i in 0..<20 {
            threads.append(SeleneChat.Thread(
                id: Int64(i),
                name: "Thread \(i) with a longer name to use more tokens",
                why: "Reason \(i) that is quite detailed",
                summary: "Summary \(i) with substantial content to fill up the token budget",
                status: "active",
                noteCount: i + 1,
                momentumScore: Double(i) / 20.0,
                lastActivityAt: Date(),
                createdAt: Date()
            ))
        }

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildBriefingContext(threads: threads, recentNotes: [])

        let tokens = builder.estimateTokens(context)
        XCTAssertLessThanOrEqual(tokens, ThinkingPartnerQueryType.briefing.tokenBudget)
    }

    func testBriefingContextSortsThreadsByMomentum() {
        let threads = [
            Thread(
                id: 1,
                name: "Low Momentum Thread",
                why: nil,
                summary: nil,
                status: "active",
                noteCount: 2,
                momentumScore: 0.2,
                lastActivityAt: Date(),
                createdAt: Date()
            ),
            Thread(
                id: 2,
                name: "High Momentum Thread",
                why: nil,
                summary: nil,
                status: "active",
                noteCount: 10,
                momentumScore: 0.9,
                lastActivityAt: Date(),
                createdAt: Date()
            )
        ]

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildBriefingContext(threads: threads, recentNotes: [])

        // High momentum should appear before low momentum
        let highIndex = context.range(of: "High Momentum Thread")!.lowerBound
        let lowIndex = context.range(of: "Low Momentum Thread")!.lowerBound
        XCTAssertLessThan(highIndex, lowIndex)
    }

    func testBriefingContextLimitsRecentNotes() {
        var notes: [Note] = []
        for i in 0..<10 {
            notes.append(Note(
                id: i,
                title: "Note \(i)",
                content: "Content \(i)",
                contentHash: "hash\(i)",
                sourceType: "drafts",
                wordCount: 2,
                characterCount: 10,
                tags: nil,
                createdAt: Date(),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ))
        }

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildBriefingContext(threads: [], recentNotes: notes)

        // Should only include up to 5 notes
        XCTAssertTrue(context.contains("Note 0"))
        XCTAssertTrue(context.contains("Note 4"))
        XCTAssertFalse(context.contains("Note 5"))
        XCTAssertFalse(context.contains("Note 9"))
    }

    // MARK: - Synthesis Context Tests

    func testBuildSynthesisContext() {
        let threads = [
            Thread(
                id: 1,
                name: "Event-Driven Architecture",
                why: "Testing strategies",
                summary: "Exploring event testing approaches",
                status: "active",
                noteCount: 5,
                momentumScore: 0.8,
                lastActivityAt: Date(),
                createdAt: Date()
            ),
            Thread(
                id: 2,
                name: "Project Journey",
                why: "Document decisions",
                summary: "Early exploration of documentation",
                status: "active",
                noteCount: 3,
                momentumScore: 0.4,
                lastActivityAt: Date().addingTimeInterval(-86400 * 3),
                createdAt: Date()
            )
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [
                Note(
                    id: 1,
                    title: "Testing approach",
                    content: "Unit vs integration",
                    contentHash: "hash1",
                    sourceType: "drafts",
                    wordCount: 3,
                    characterCount: 18,
                    tags: nil,
                    createdAt: Date(),
                    importedAt: Date(),
                    processedAt: nil,
                    exportedAt: nil,
                    status: "processed",
                    exportedToObsidian: false,
                    sourceUUID: nil,
                    testRun: nil
                ),
                Note(
                    id: 2,
                    title: "Event schemas",
                    content: "Schema validation",
                    contentHash: "hash2",
                    sourceType: "drafts",
                    wordCount: 2,
                    characterCount: 17,
                    tags: nil,
                    createdAt: Date(),
                    importedAt: Date(),
                    processedAt: nil,
                    exportedAt: nil,
                    status: "processed",
                    exportedToObsidian: false,
                    sourceUUID: nil,
                    testRun: nil
                )
            ],
            2: [
                Note(
                    id: 3,
                    title: "Why document",
                    content: "Future reference",
                    contentHash: "hash3",
                    sourceType: "drafts",
                    wordCount: 2,
                    characterCount: 16,
                    tags: nil,
                    createdAt: Date(),
                    importedAt: Date(),
                    processedAt: nil,
                    exportedAt: nil,
                    status: "processed",
                    exportedToObsidian: false,
                    sourceUUID: nil,
                    testRun: nil
                )
            ]
        ]

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        // Should include all threads
        XCTAssertTrue(context.contains("Event-Driven Architecture"))
        XCTAssertTrue(context.contains("Project Journey"))

        // Should include note titles
        XCTAssertTrue(context.contains("Testing approach"))
        XCTAssertTrue(context.contains("Why document"))

        // Should have cross-thread section header
        XCTAssertTrue(context.contains("Threads for Prioritization"))
    }

    func testSynthesisContextLimitsNotesPerThread() {
        let thread = Thread(
            id: 1,
            name: "Test Thread",
            why: nil,
            summary: nil,
            status: "active",
            noteCount: 10,
            momentumScore: 0.5,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        // Create 10 notes
        var notes: [Note] = []
        for i in 0..<10 {
            notes.append(Note(
                id: i,
                title: "Note \(i)",
                content: "Content",
                contentHash: "hash\(i)",
                sourceType: "drafts",
                wordCount: 1,
                characterCount: 7,
                tags: nil,
                createdAt: Date(),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ))
        }

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildSynthesisContext(threads: [thread], notesPerThread: [1: notes])

        // Should only show 3 notes + "...and N more"
        XCTAssertTrue(context.contains("Note 0"))
        XCTAssertTrue(context.contains("Note 1"))
        XCTAssertTrue(context.contains("Note 2"))
        XCTAssertTrue(context.contains("...and 7 more"))
        XCTAssertFalse(context.contains("Note 9"))
    }

    func testSynthesisContextSortsThreadsByMomentum() {
        let threads = [
            Thread(
                id: 1,
                name: "Low Momentum Thread",
                why: nil,
                summary: nil,
                status: "active",
                noteCount: 2,
                momentumScore: 0.2,
                lastActivityAt: Date(),
                createdAt: Date()
            ),
            Thread(
                id: 2,
                name: "High Momentum Thread",
                why: nil,
                summary: nil,
                status: "active",
                noteCount: 10,
                momentumScore: 0.9,
                lastActivityAt: Date(),
                createdAt: Date()
            )
        ]

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildSynthesisContext(threads: threads, notesPerThread: [:])

        // High momentum should appear before low momentum
        let highIndex = context.range(of: "High Momentum Thread")!.lowerBound
        let lowIndex = context.range(of: "Low Momentum Thread")!.lowerBound
        XCTAssertLessThan(highIndex, lowIndex)
    }

    func testSynthesisContextRespectsTokenBudget() {
        // Create many threads to exceed budget
        var threads: [SeleneChat.Thread] = []
        for i in 0..<50 {
            threads.append(SeleneChat.Thread(
                id: Int64(i),
                name: "Thread \(i) with a longer name to use more tokens",
                why: "Reason \(i) that is quite detailed and verbose",
                summary: "Summary \(i) with substantial content to fill up the token budget quickly",
                status: "active",
                noteCount: i + 1,
                momentumScore: Double(i) / 50.0,
                lastActivityAt: Date(),
                createdAt: Date()
            ))
        }

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildSynthesisContext(threads: threads, notesPerThread: [:])

        let tokens = builder.estimateTokens(context)
        XCTAssertLessThanOrEqual(tokens, ThinkingPartnerQueryType.synthesis.tokenBudget)

        // Should include truncation message
        XCTAssertTrue(context.contains("[Additional threads omitted"))
    }

    // MARK: - Deep-Dive Context Tests

    func testBuildDeepDiveContext() {
        let thread = Thread(
            id: 1,
            name: "Event-Driven Architecture",
            why: "Exploring testing strategies for event-driven systems",
            summary: "Notes about different testing approaches",
            status: "active",
            noteCount: 3,
            momentumScore: 0.8,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        let notes = [
            Note(
                id: 1,
                title: "Unit tests insufficient",
                content: "Unit tests don't catch event flow issues.",
                contentHash: "hash1",
                sourceType: "drafts",
                wordCount: 6,
                characterCount: 43,
                tags: nil,
                createdAt: Date().addingTimeInterval(-86400 * 2),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ),
            Note(
                id: 2,
                title: "Integration tests slow",
                content: "Integration tests are slow but catch real bugs.",
                contentHash: "hash2",
                sourceType: "drafts",
                wordCount: 8,
                characterCount: 47,
                tags: nil,
                createdAt: Date().addingTimeInterval(-86400),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ),
            Note(
                id: 3,
                title: "Contract testing idea",
                content: "Maybe contract tests are the middle ground?",
                contentHash: "hash3",
                sourceType: "drafts",
                wordCount: 7,
                characterCount: 43,
                tags: nil,
                createdAt: Date(),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            )
        ]

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

        // Should include thread details
        XCTAssertTrue(context.contains("Event-Driven Architecture"))
        XCTAssertTrue(context.contains("Exploring testing strategies"))

        // Should include full note content
        XCTAssertTrue(context.contains("Unit tests don't catch"))
        XCTAssertTrue(context.contains("Integration tests are slow"))
        XCTAssertTrue(context.contains("contract tests are the middle ground"))

        // Should have notes section header
        XCTAssertTrue(context.contains("Thread Notes"))
    }

    func testDeepDiveContextRespectsTokenBudget() {
        let thread = Thread(
            id: 1,
            name: "Test Thread",
            why: nil,
            summary: nil,
            status: "active",
            noteCount: 50,
            momentumScore: 0.5,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        // Create many notes with substantial content
        var notes: [Note] = []
        for i in 0..<50 {
            notes.append(Note(
                id: i,
                title: "Note \(i)",
                content: String(repeating: "This is substantial content for note \(i). ", count: 20),
                contentHash: "hash\(i)",
                sourceType: "drafts",
                wordCount: 140,
                characterCount: 880,
                tags: nil,
                createdAt: Date().addingTimeInterval(Double(-i * 86400)),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ))
        }

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

        let tokens = builder.estimateTokens(context)
        XCTAssertLessThanOrEqual(tokens, ThinkingPartnerQueryType.deepDive.tokenBudget)
    }

    func testDeepDiveContextChronologicalOrder() {
        let thread = Thread(
            id: 1,
            name: "Test Thread",
            why: nil,
            summary: nil,
            status: "active",
            noteCount: 3,
            momentumScore: 0.5,
            lastActivityAt: Date(),
            createdAt: Date()
        )

        let notes = [
            Note(
                id: 3,
                title: "Third",
                content: "Content 3",
                contentHash: "hash3",
                sourceType: "drafts",
                wordCount: 2,
                characterCount: 9,
                tags: nil,
                createdAt: Date(),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ),
            Note(
                id: 1,
                title: "First",
                content: "Content 1",
                contentHash: "hash1",
                sourceType: "drafts",
                wordCount: 2,
                characterCount: 9,
                tags: nil,
                createdAt: Date().addingTimeInterval(-86400 * 2),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            ),
            Note(
                id: 2,
                title: "Second",
                content: "Content 2",
                contentHash: "hash2",
                sourceType: "drafts",
                wordCount: 2,
                characterCount: 9,
                tags: nil,
                createdAt: Date().addingTimeInterval(-86400),
                importedAt: Date(),
                processedAt: nil,
                exportedAt: nil,
                status: "processed",
                exportedToObsidian: false,
                sourceUUID: nil,
                testRun: nil
            )
        ]

        let builder = ThinkingPartnerContextBuilder()
        let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

        // First should appear before Second, Second before Third
        let firstIndex = context.range(of: "First")?.lowerBound
        let secondIndex = context.range(of: "Second")?.lowerBound
        let thirdIndex = context.range(of: "Third")?.lowerBound

        XCTAssertNotNil(firstIndex)
        XCTAssertNotNil(secondIndex)
        XCTAssertNotNil(thirdIndex)
        XCTAssertTrue(firstIndex! < secondIndex!)
        XCTAssertTrue(secondIndex! < thirdIndex!)
    }
}
