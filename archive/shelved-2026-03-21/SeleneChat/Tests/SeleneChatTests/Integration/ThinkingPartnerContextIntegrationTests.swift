import SeleneShared
import XCTest
@testable import SeleneChat

final class ThinkingPartnerContextIntegrationTests: XCTestCase {

    // MARK: - Test Helpers

    /// Create a test thread with default values
    private func makeThread(
        id: Int64,
        name: String,
        why: String? = nil,
        summary: String? = nil,
        status: String = "active",
        noteCount: Int = 2,
        momentumScore: Double? = 0.5,
        lastActivityAt: Date? = Date(),
        createdAt: Date = Date()
    ) -> SeleneChat.Thread {
        return SeleneChat.Thread(
            id: id,
            name: name,
            why: why,
            summary: summary,
            status: status,
            noteCount: noteCount,
            momentumScore: momentumScore,
            lastActivityAt: lastActivityAt,
            createdAt: createdAt
        )
    }

    /// Create a test note with default values
    private func makeNote(
        id: Int,
        title: String,
        content: String,
        createdAt: Date = Date()
    ) -> Note {
        return Note(
            id: id,
            title: title,
            content: content,
            contentHash: "hash\(id)",
            sourceType: "drafts",
            wordCount: content.split(separator: " ").count,
            characterCount: content.count,
            tags: nil,
            createdAt: createdAt,
            importedAt: Date(),
            processedAt: nil,
            exportedAt: nil,
            status: "processed",
            exportedToObsidian: false,
            sourceUUID: nil,
            testRun: nil
        )
    }

    // MARK: - Valid Context Tests

    /// Test that context builder produces valid context for each query type
    func testAllQueryTypesProduceValidContext() {
        let builder = ThinkingPartnerContextBuilder()

        let thread = makeThread(
            id: 1,
            name: "Test Thread",
            why: "Test reason",
            summary: "Test summary"
        )

        let note = makeNote(id: 1, title: "Test Note", content: "Test content")

        // Briefing
        let briefingContext = builder.buildBriefingContext(threads: [thread], recentNotes: [note])
        XCTAssertFalse(briefingContext.isEmpty)
        XCTAssertTrue(builder.estimateTokens(briefingContext) <= ThinkingPartnerQueryType.briefing.tokenBudget)

        // Synthesis
        let synthesisContext = builder.buildSynthesisContext(threads: [thread], notesPerThread: [1: [note]])
        XCTAssertFalse(synthesisContext.isEmpty)
        XCTAssertTrue(builder.estimateTokens(synthesisContext) <= ThinkingPartnerQueryType.synthesis.tokenBudget)

        // Deep-dive
        let deepDiveContext = builder.buildDeepDiveContext(thread: thread, notes: [note])
        XCTAssertFalse(deepDiveContext.isEmpty)
        XCTAssertTrue(builder.estimateTokens(deepDiveContext) <= ThinkingPartnerQueryType.deepDive.tokenBudget)
    }

    // MARK: - Empty Input Tests

    /// Test that empty inputs produce graceful output
    func testEmptyInputsHandledGracefully() {
        let builder = ThinkingPartnerContextBuilder()

        // Empty briefing
        let briefingContext = builder.buildBriefingContext(threads: [], recentNotes: [])
        XCTAssertTrue(briefingContext.contains("Active Threads"))  // Header still present

        // Empty synthesis
        let synthesisContext = builder.buildSynthesisContext(threads: [], notesPerThread: [:])
        XCTAssertTrue(synthesisContext.contains("Prioritization"))

        // Deep-dive with no notes
        let thread = SeleneChat.Thread(
            id: 1,
            name: "Empty Thread",
            why: nil,
            summary: nil,
            status: "active",
            noteCount: 0,
            momentumScore: nil,
            lastActivityAt: nil,
            createdAt: Date()
        )
        let deepDiveContext = builder.buildDeepDiveContext(thread: thread, notes: [])
        XCTAssertTrue(deepDiveContext.contains("Empty Thread"))
    }

    // MARK: - Token Budget Tests

    /// Test token budgets are respected under load
    func testTokenBudgetsUnderLoad() {
        let builder = ThinkingPartnerContextBuilder()

        // Create many threads and notes
        var threads: [SeleneChat.Thread] = []
        var notesPerThread: [Int64: [Note]] = [:]

        for i in 0..<30 {
            let threadId = Int64(i)
            threads.append(makeThread(
                id: threadId,
                name: "Thread \(i) with a long descriptive name",
                why: "Detailed reason for thread \(i) existence",
                summary: "Comprehensive summary of thread \(i) covering multiple topics and ideas",
                noteCount: 10,
                momentumScore: Double(30 - i) / 30.0
            ))

            var notes: [Note] = []
            for j in 0..<10 {
                notes.append(makeNote(
                    id: i * 10 + j,
                    title: "Note \(j) for Thread \(i)",
                    content: String(repeating: "Content for note \(j). ", count: 10)
                ))
            }
            notesPerThread[threadId] = notes
        }

        // All context types should respect their budgets
        let briefing = builder.buildBriefingContext(threads: threads, recentNotes: notesPerThread[0] ?? [])
        XCTAssertLessThanOrEqual(builder.estimateTokens(briefing), ThinkingPartnerQueryType.briefing.tokenBudget)

        let synthesis = builder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)
        XCTAssertLessThanOrEqual(builder.estimateTokens(synthesis), ThinkingPartnerQueryType.synthesis.tokenBudget)

        let deepDive = builder.buildDeepDiveContext(thread: threads[0], notes: notesPerThread[0] ?? [])
        XCTAssertLessThanOrEqual(builder.estimateTokens(deepDive), ThinkingPartnerQueryType.deepDive.tokenBudget)
    }

    // MARK: - Context Content Verification

    /// Test that briefing context includes expected sections and content
    func testBriefingContextContent() {
        let builder = ThinkingPartnerContextBuilder()

        let threads = [
            makeThread(id: 1, name: "High Priority Thread", momentumScore: 0.9),
            makeThread(id: 2, name: "Low Priority Thread", momentumScore: 0.2)
        ]

        let notes = [
            makeNote(id: 1, title: "Recent Note 1", content: "Content 1"),
            makeNote(id: 2, title: "Recent Note 2", content: "Content 2")
        ]

        let context = builder.buildBriefingContext(threads: threads, recentNotes: notes)

        // Verify structure
        XCTAssertTrue(context.contains("## Active Threads"))
        XCTAssertTrue(context.contains("## Recent Notes"))

        // Verify thread content
        XCTAssertTrue(context.contains("High Priority Thread"))
        XCTAssertTrue(context.contains("Low Priority Thread"))

        // Verify note content
        XCTAssertTrue(context.contains("Recent Note 1"))
        XCTAssertTrue(context.contains("Recent Note 2"))
    }

    /// Test that synthesis context includes expected sections and content
    func testSynthesisContextContent() {
        let builder = ThinkingPartnerContextBuilder()

        let threads = [
            makeThread(id: 1, name: "Project Alpha", why: "Exploring new architecture"),
            makeThread(id: 2, name: "Project Beta", summary: "Ongoing refactoring work")
        ]

        let notesPerThread: [Int64: [Note]] = [
            1: [makeNote(id: 1, title: "Alpha Note 1", content: "Content A1")],
            2: [makeNote(id: 2, title: "Beta Note 1", content: "Content B1")]
        ]

        let context = builder.buildSynthesisContext(threads: threads, notesPerThread: notesPerThread)

        // Verify structure
        XCTAssertTrue(context.contains("## Threads for Prioritization"))

        // Verify threads included
        XCTAssertTrue(context.contains("Project Alpha"))
        XCTAssertTrue(context.contains("Project Beta"))

        // Verify note titles included
        XCTAssertTrue(context.contains("Alpha Note 1"))
        XCTAssertTrue(context.contains("Beta Note 1"))
    }

    /// Test that deep-dive context includes expected sections and content
    func testDeepDiveContextContent() {
        let builder = ThinkingPartnerContextBuilder()

        let thread = makeThread(
            id: 1,
            name: "Deep Dive Thread",
            why: "Critical analysis needed",
            summary: "Comprehensive thread summary"
        )

        let notes = [
            makeNote(
                id: 1,
                title: "First Note",
                content: "Detailed first note content",
                createdAt: Date().addingTimeInterval(-86400)
            ),
            makeNote(
                id: 2,
                title: "Second Note",
                content: "Detailed second note content",
                createdAt: Date()
            )
        ]

        let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

        // Verify structure
        XCTAssertTrue(context.contains("## Thread: Deep Dive Thread"))
        XCTAssertTrue(context.contains("## Thread Notes (chronological)"))

        // Verify thread metadata
        XCTAssertTrue(context.contains("Critical analysis needed"))
        XCTAssertTrue(context.contains("Comprehensive thread summary"))

        // Verify full note content (not just titles)
        XCTAssertTrue(context.contains("Detailed first note content"))
        XCTAssertTrue(context.contains("Detailed second note content"))
    }

    // MARK: - Edge Cases

    /// Test handling of threads with nil optional values
    func testThreadsWithNilValues() {
        let builder = ThinkingPartnerContextBuilder()

        let thread = SeleneChat.Thread(
            id: 1,
            name: "Minimal Thread",
            why: nil,
            summary: nil,
            status: "active",
            noteCount: 0,
            momentumScore: nil,
            lastActivityAt: nil,
            createdAt: Date()
        )

        // Should not crash with nil values
        let briefing = builder.buildBriefingContext(threads: [thread], recentNotes: [])
        XCTAssertTrue(briefing.contains("Minimal Thread"))

        let synthesis = builder.buildSynthesisContext(threads: [thread], notesPerThread: [:])
        XCTAssertTrue(synthesis.contains("Minimal Thread"))

        let deepDive = builder.buildDeepDiveContext(thread: thread, notes: [])
        XCTAssertTrue(deepDive.contains("Minimal Thread"))
    }

    /// Test handling of very long content
    func testVeryLongContent() {
        let builder = ThinkingPartnerContextBuilder()

        // Thread with very long summary
        let thread = makeThread(
            id: 1,
            name: "Thread with Long Content",
            summary: String(repeating: "This is a very long summary that goes on and on. ", count: 50)
        )

        // Note with very long content
        let note = makeNote(
            id: 1,
            title: "Note with Long Content",
            content: String(repeating: "This is very long note content that continues. ", count: 100)
        )

        // All context types should still respect budgets
        let briefing = builder.buildBriefingContext(threads: [thread], recentNotes: [note])
        XCTAssertLessThanOrEqual(builder.estimateTokens(briefing), ThinkingPartnerQueryType.briefing.tokenBudget)

        let synthesis = builder.buildSynthesisContext(threads: [thread], notesPerThread: [1: [note]])
        XCTAssertLessThanOrEqual(builder.estimateTokens(synthesis), ThinkingPartnerQueryType.synthesis.tokenBudget)

        let deepDive = builder.buildDeepDiveContext(thread: thread, notes: [note])
        XCTAssertLessThanOrEqual(builder.estimateTokens(deepDive), ThinkingPartnerQueryType.deepDive.tokenBudget)
    }

    /// Test handling of special characters in content
    func testSpecialCharactersInContent() {
        let builder = ThinkingPartnerContextBuilder()

        let thread = makeThread(
            id: 1,
            name: "Thread with \"quotes\" & <special> chars",
            why: "Why with 'apostrophes' and (parentheses)",
            summary: "Summary with\nnewlines\tand\ttabs"
        )

        let note = makeNote(
            id: 1,
            title: "Note [1] with {braces}",
            content: "Content with @mentions, #hashtags, and $symbols"
        )

        // Should handle special characters without crashing
        let briefing = builder.buildBriefingContext(threads: [thread], recentNotes: [note])
        XCTAssertFalse(briefing.isEmpty)

        let synthesis = builder.buildSynthesisContext(threads: [thread], notesPerThread: [1: [note]])
        XCTAssertFalse(synthesis.isEmpty)

        let deepDive = builder.buildDeepDiveContext(thread: thread, notes: [note])
        XCTAssertFalse(deepDive.isEmpty)
    }

    // MARK: - Token Budget Boundary Tests

    /// Test exact boundary conditions for token budgets
    func testTokenBudgetBoundaries() {
        let builder = ThinkingPartnerContextBuilder()

        // Create content that approaches but doesn't exceed each budget
        for queryType in [ThinkingPartnerQueryType.briefing, .synthesis, .deepDive] {
            let budget = queryType.tokenBudget
            let charLimit = budget * 4  // 4 chars per token estimate

            // Create content just under the limit
            let contentJustUnder = String(repeating: "a", count: charLimit - 100)
            let tokensUnder = builder.estimateTokens(contentJustUnder)
            XCTAssertLessThan(tokensUnder, budget, "Content should be under budget for \(queryType)")

            // Create content over the limit
            let contentOver = String(repeating: "a", count: charLimit + 100)
            let tokensOver = builder.estimateTokens(contentOver)
            XCTAssertGreaterThan(tokensOver, budget, "Content should be over budget for \(queryType)")
        }
    }

    // MARK: - Ordering Tests

    /// Test that threads are consistently ordered by momentum in briefing and synthesis
    func testConsistentMomentumOrdering() {
        let builder = ThinkingPartnerContextBuilder()

        let threads = [
            makeThread(id: 1, name: "Medium Thread", momentumScore: 0.5),
            makeThread(id: 2, name: "High Thread", momentumScore: 0.9),
            makeThread(id: 3, name: "Low Thread", momentumScore: 0.1)
        ]

        let briefingContext = builder.buildBriefingContext(threads: threads, recentNotes: [])
        let synthesisContext = builder.buildSynthesisContext(threads: threads, notesPerThread: [:])

        // In both contexts, High should come before Medium, and Medium before Low
        for context in [briefingContext, synthesisContext] {
            let highIndex = context.range(of: "High Thread")!.lowerBound
            let mediumIndex = context.range(of: "Medium Thread")!.lowerBound
            let lowIndex = context.range(of: "Low Thread")!.lowerBound

            XCTAssertLessThan(highIndex, mediumIndex, "High should come before Medium")
            XCTAssertLessThan(mediumIndex, lowIndex, "Medium should come before Low")
        }
    }

    /// Test that notes are chronologically ordered in deep-dive context
    func testChronologicalNoteOrdering() {
        let builder = ThinkingPartnerContextBuilder()

        let thread = makeThread(id: 1, name: "Chronological Test")

        let notes = [
            makeNote(id: 3, title: "Note C (newest)", content: "C", createdAt: Date()),
            makeNote(id: 1, title: "Note A (oldest)", content: "A", createdAt: Date().addingTimeInterval(-86400 * 2)),
            makeNote(id: 2, title: "Note B (middle)", content: "B", createdAt: Date().addingTimeInterval(-86400))
        ]

        let context = builder.buildDeepDiveContext(thread: thread, notes: notes)

        // Notes should appear in chronological order: A, B, C
        let aIndex = context.range(of: "Note A")!.lowerBound
        let bIndex = context.range(of: "Note B")!.lowerBound
        let cIndex = context.range(of: "Note C")!.lowerBound

        XCTAssertLessThan(aIndex, bIndex, "A (oldest) should come before B")
        XCTAssertLessThan(bIndex, cIndex, "B should come before C (newest)")
    }
}
