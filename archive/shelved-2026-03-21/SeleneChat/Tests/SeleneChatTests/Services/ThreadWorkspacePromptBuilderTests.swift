import SeleneShared
import XCTest
@testable import SeleneChat

final class ThreadWorkspacePromptBuilderTests: XCTestCase {

    // MARK: - Initial Prompt Tests

    func testBuildInitialPromptIncludesThreadContext() {
        let thread = Thread.mock(
            name: "Voice Input Feature",
            why: "Reduce friction for captures",
            summary: "Phase 1 push-to-talk complete"
        )

        let notes = [
            Note.mock(id: 1, title: "Speech recognition research", content: "Explored SFSpeechRecognizer API."),
            Note.mock(id: 2, title: "UX for voice", content: "Push-to-talk feels more natural than always-on.")
        ]

        let tasks = [
            ThreadTask.mock(thingsTaskId: "VOICE-001", title: "Add global hotkey"),
            ThreadTask.mock(thingsTaskId: "VOICE-002", title: "Test on external mic", completedAt: Date())
        ]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes, tasks: tasks)

        // Should include thread name
        XCTAssertTrue(prompt.contains("Voice Input Feature"), "Prompt should include thread name")

        // Should include note content
        XCTAssertTrue(prompt.contains("Speech recognition research"), "Prompt should include note titles")
        XCTAssertTrue(prompt.contains("SFSpeechRecognizer"), "Prompt should include note content")
    }

    func testBuildInitialPromptIncludesTaskState() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let openTask = ThreadTask.mock(thingsTaskId: "T-001", title: "Open task")
        let doneTask = ThreadTask.mock(thingsTaskId: "T-002", title: "Done task", completedAt: Date())
        let tasks = [openTask, doneTask]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes, tasks: tasks)

        // Should include task summary
        XCTAssertTrue(prompt.contains("1 open"), "Prompt should mention open task count")
        XCTAssertTrue(prompt.contains("1 completed"), "Prompt should mention completed task count")
    }

    func testBuildInitialPromptIncludesTaskTitles() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]

        let tasks = [
            ThreadTask.mock(thingsTaskId: "T-001", title: "Research API options"),
            ThreadTask.mock(thingsTaskId: "T-002", title: "Write integration test")
        ]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: notes, tasks: tasks)

        XCTAssertTrue(prompt.contains("Research API options"), "Prompt should include task titles")
        XCTAssertTrue(prompt.contains("Write integration test"), "Prompt should include task titles")
    }

    func testBuildInitialPromptIncludesADHDFraming() {
        let thread = Thread.mock(name: "Test Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: [Note.mock()], tasks: [])

        XCTAssertTrue(prompt.lowercased().contains("adhd"), "Prompt should mention ADHD")
        XCTAssertTrue(prompt.lowercased().contains("thinking partner"), "Prompt should include thinking partner framing")
    }

    func testBuildInitialPromptIncludesActionMarkers() {
        let thread = Thread.mock(name: "Test Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: [Note.mock()], tasks: [])

        XCTAssertTrue(prompt.contains("[ACTION:"), "Prompt should include action marker format")
        XCTAssertTrue(prompt.contains("ENERGY:"), "Prompt should include energy level")
        XCTAssertTrue(prompt.contains("TIMEFRAME:"), "Prompt should include timeframe")
    }

    func testBuildInitialPromptWithNoTasks() {
        let thread = Thread.mock(name: "Fresh Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: [Note.mock()], tasks: [])

        XCTAssertTrue(prompt.contains("No tasks"), "Prompt should indicate no tasks exist yet")
    }

    // MARK: - Follow-Up Prompt Tests

    func testBuildFollowUpPromptIncludesConversationHistory() {
        let thread = Thread.mock(name: "Test Thread")
        let conversationHistory = """
        User: What should I focus on next?
        Assistant: Based on your notes, the API integration seems most urgent.
        """

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: [Note.mock()],
            tasks: [],
            conversationHistory: conversationHistory,
            currentQuery: "Break that down into tasks"
        )

        XCTAssertTrue(prompt.contains("What should I focus on next?"), "Prompt should include conversation history")
        XCTAssertTrue(prompt.contains("API integration seems most urgent"), "Prompt should include assistant response")
    }

    func testBuildFollowUpPromptIncludesCurrentQuery() {
        let thread = Thread.mock(name: "Test Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: [Note.mock()],
            tasks: [],
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "What are the next steps?"
        )

        XCTAssertTrue(prompt.contains("What are the next steps?"), "Prompt should include current query")
    }

    func testBuildFollowUpPromptIncludesTaskState() {
        let thread = Thread.mock(name: "Test Thread")
        let tasks = [
            ThreadTask.mock(thingsTaskId: "T-001", title: "Open task"),
            ThreadTask.mock(thingsTaskId: "T-002", title: "Done task", completedAt: Date())
        ]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: [Note.mock()],
            tasks: tasks,
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next?"
        )

        XCTAssertTrue(prompt.contains("1 open"), "Follow-up should include current task state")
    }

    func testBuildFollowUpPromptIncludesActionMarkers() {
        let thread = Thread.mock(name: "Test Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: [Note.mock()],
            tasks: [],
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next?"
        )

        XCTAssertTrue(prompt.contains("[ACTION:"), "Follow-up prompt should include action marker format")
    }

    func testActionMarkersAreConditional() {
        let thread = Thread.mock(name: "Test Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(thread: thread, notes: [Note.mock()], tasks: [])

        XCTAssertTrue(
            prompt.contains("collaboratively identified"),
            "Action markers should be tied to collaborative identification of steps"
        )
    }

    func testFollowUpActionMarkersAreConditional() {
        let thread = Thread.mock(name: "Test Thread")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: [Note.mock()],
            tasks: [],
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next?"
        )

        XCTAssertTrue(
            prompt.contains("collaboratively identified"),
            "Follow-up action markers should be tied to collaborative identification"
        )
    }

    func testBuildFollowUpPromptIncludesThreadContext() {
        let thread = Thread.mock(name: "Architecture Decisions")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: thread,
            notes: [Note.mock()],
            tasks: [],
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next?"
        )

        XCTAssertTrue(prompt.contains("Architecture Decisions"), "Follow-up should include thread name")
    }

    // MARK: - What's Next Tests

    func testIsWhatsNextQueryDetectsVariations() {
        let builder = ThreadWorkspacePromptBuilder()

        XCTAssertTrue(builder.isWhatsNextQuery("what's next"))
        XCTAssertTrue(builder.isWhatsNextQuery("What's next?"))
        XCTAssertTrue(builder.isWhatsNextQuery("what should I do next"))
        XCTAssertTrue(builder.isWhatsNextQuery("What should I work on?"))
        XCTAssertTrue(builder.isWhatsNextQuery("what do I do now"))
        XCTAssertFalse(builder.isWhatsNextQuery("break down the auth task"))
        XCTAssertFalse(builder.isWhatsNextQuery("tell me about this thread"))
    }

    // MARK: - Interactive Identity Tests

    func testInitialPromptHasInteractiveIdentity() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertTrue(
            prompt.contains("interactive thinking partner"),
            "Prompt should use interactive thinking partner identity"
        )
        XCTAssertFalse(
            prompt.contains("Respond naturally to whatever"),
            "Prompt should NOT use old generic instruction"
        )
    }

    func testInitialPromptDescribesThingsCapability() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertTrue(
            prompt.contains("Things"),
            "Prompt should mention Things task manager by name"
        )
        XCTAssertTrue(
            prompt.lowercased().contains("capability") || prompt.lowercased().contains("capabilities"),
            "Prompt should frame action markers as a capability"
        )
    }

    func testInitialPromptHasNoBriefWordLimit() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertFalse(prompt.contains("under 200 words"))
        XCTAssertFalse(prompt.contains("under 150 words"))
        XCTAssertFalse(prompt.contains("under 100 words"))
    }

    func testInitialPromptCoachesAgainstSummarizing() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildInitialPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertTrue(
            prompt.lowercased().contains("not summarize") || prompt.lowercased().contains("not a summarizer") || prompt.lowercased().contains("never summarize"),
            "Prompt should explicitly discourage summarizing"
        )
    }

    func testChunkBasedInitialPromptHasInteractiveIdentity() {
        let builder = ThreadWorkspacePromptBuilder()
        let chunks = [(chunk: NoteChunk.mock(id: 1, content: "Test chunk"), similarity: Float(0.8))]
        let prompt = builder.buildInitialPromptWithChunks(
            thread: Thread.mock(name: "Test"),
            retrievedChunks: chunks,
            tasks: []
        )

        XCTAssertTrue(prompt.contains("interactive thinking partner"))
        XCTAssertFalse(prompt.contains("under 200 words"))
    }

    func testFollowUpPromptHasNoBriefWordLimit() {
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildFollowUpPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: [],
            conversationHistory: "User: Q\nAssistant: A",
            currentQuery: "Next?"
        )

        XCTAssertFalse(prompt.contains("under 150 words"))
    }

    func testBuildWhatsNextPromptIncludesTaskState() {
        let thread = Thread.mock(
            name: "ADHD System",
            why: "Build tools for executive function",
            summary: "Phase 1 complete"
        )

        let openTask = ThreadTask.mock(thingsTaskId: "T1", title: "Research time-blocking")
        let completedTask = ThreadTask.mock(thingsTaskId: "T2", title: "Write principles doc", completedAt: Date())

        let notes = [
            Note.mock(id: 1, title: "ADHD Research", content: "Focus on externalization")
        ]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildWhatsNextPrompt(thread: thread, notes: notes, tasks: [openTask, completedTask])

        XCTAssertTrue(prompt.contains("Research time-blocking"), "Should include open task")
        XCTAssertTrue(prompt.contains("Write principles doc"), "Should include completed task")
        XCTAssertTrue(prompt.contains("2-3"), "Should propose multiple options")
    }

    func testBuildWhatsNextPromptProposesMultipleOptions() {
        let thread = Thread.mock(name: "Project X", why: "Ship the feature")
        let notes = [Note.mock(id: 1, title: "Research", content: "Found three approaches")]
        let tasks = [ThreadTask.mock(thingsTaskId: "T-001", title: "Open task")]

        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildWhatsNextPrompt(thread: thread, notes: notes, tasks: tasks)

        XCTAssertTrue(
            prompt.contains("2-3") || prompt.contains("two or three") || prompt.contains("multiple"),
            "What's Next prompt should ask LLM to propose multiple options"
        )
        XCTAssertFalse(
            prompt.contains("recommend ONE"),
            "What's Next prompt should NOT limit to one recommendation"
        )
        XCTAssertFalse(
            prompt.contains("under 100 words"),
            "What's Next prompt should NOT have 100-word limit"
        )
    }

    func testBuildWhatsNextPromptAsksWhichResonates() {
        let thread = Thread.mock(name: "Test")
        let builder = ThreadWorkspacePromptBuilder()
        let prompt = builder.buildWhatsNextPrompt(thread: thread, notes: [Note.mock()], tasks: [])

        XCTAssertTrue(
            prompt.lowercased().contains("resonat") || prompt.lowercased().contains("which"),
            "What's Next prompt should ask user which option resonates"
        )
    }

    // MARK: - Planning Detection Tests

    func testIsPlanningQueryDetectsCommonPatterns() {
        let builder = ThreadWorkspacePromptBuilder()

        XCTAssertTrue(builder.isPlanningQuery("help me make a plan"))
        XCTAssertTrue(builder.isPlanningQuery("Help me figure out next steps"))
        XCTAssertTrue(builder.isPlanningQuery("break this down"))
        XCTAssertTrue(builder.isPlanningQuery("how should I approach this?"))
        XCTAssertTrue(builder.isPlanningQuery("what are my options"))
        XCTAssertTrue(builder.isPlanningQuery("help me think through this"))
        XCTAssertTrue(builder.isPlanningQuery("can you help me prioritize"))
        XCTAssertTrue(builder.isPlanningQuery("I need to figure out what to do"))
        XCTAssertTrue(builder.isPlanningQuery("help me work through this"))
        XCTAssertTrue(builder.isPlanningQuery("what should my next move be"))
    }

    func testIsPlanningQueryRejectsNonPlanningQueries() {
        let builder = ThreadWorkspacePromptBuilder()

        XCTAssertFalse(builder.isPlanningQuery("tell me about this thread"))
        XCTAssertFalse(builder.isPlanningQuery("summarize my notes"))
        XCTAssertFalse(builder.isPlanningQuery("what is this thread about"))
        XCTAssertFalse(builder.isPlanningQuery("when did I last update this"))
    }

    func testIsPlanningQueryHasAtLeast20Patterns() {
        let builder = ThreadWorkspacePromptBuilder()

        let planningPhrases = [
            "help me make a plan",
            "break this down",
            "how should I approach",
            "what are my options",
            "figure out",
            "think through",
            "work through",
            "prioritize",
            "decide between",
            "next move",
            "help me plan",
            "make a plan",
            "create a plan",
            "come up with a plan",
            "what should I do about",
            "how do I tackle",
            "where do I start",
            "help me decide",
            "map this out",
            "lay out the steps",
        ]

        var detected = 0
        for phrase in planningPhrases {
            if builder.isPlanningQuery(phrase) {
                detected += 1
            }
        }

        XCTAssertGreaterThanOrEqual(detected, 20, "Should detect at least 20 planning patterns, got \(detected)")
    }

    // MARK: - Planning Prompt Tests

    func testBuildPlanningPromptCoachesClarifyingQuestions() {
        let thread = Thread.mock(name: "Dog Training", why: "Train the dog")
        let notes = [Note.mock(id: 1, title: "Leash training", content: "Positive reinforcement works best")]
        let builder = ThreadWorkspacePromptBuilder()

        let prompt = builder.buildPlanningPrompt(
            thread: thread,
            notes: notes,
            tasks: [],
            userQuery: "help me make a plan for this"
        )

        XCTAssertTrue(
            prompt.lowercased().contains("clarifying question") || prompt.lowercased().contains("clarifying questions"),
            "Planning prompt should coach asking clarifying questions"
        )
    }

    func testBuildPlanningPromptIncludesUserQuery() {
        let builder = ThreadWorkspacePromptBuilder()

        let prompt = builder.buildPlanningPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: [],
            userQuery: "help me break down the API integration"
        )

        XCTAssertTrue(prompt.contains("help me break down the API integration"))
    }

    func testBuildPlanningPromptIncludesThreadContext() {
        let builder = ThreadWorkspacePromptBuilder()

        let prompt = builder.buildPlanningPrompt(
            thread: Thread.mock(name: "Voice Features"),
            notes: [Note.mock(id: 1, title: "TTS Research", content: "AVSpeechSynthesizer works offline")],
            tasks: [],
            userQuery: "help me plan"
        )

        XCTAssertTrue(prompt.contains("Voice Features"))
        XCTAssertTrue(prompt.contains("TTS Research"))
    }

    func testBuildPlanningPromptIncludesTaskState() {
        let builder = ThreadWorkspacePromptBuilder()
        let tasks = [
            ThreadTask.mock(thingsTaskId: "T-001", title: "Research APIs"),
            ThreadTask.mock(thingsTaskId: "T-002", title: "Write tests", completedAt: Date())
        ]

        let prompt = builder.buildPlanningPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: tasks,
            userQuery: "help me plan"
        )

        XCTAssertTrue(prompt.contains("Research APIs"))
    }

    func testBuildPlanningPromptMentionsThingsCapability() {
        let builder = ThreadWorkspacePromptBuilder()

        let prompt = builder.buildPlanningPrompt(
            thread: Thread.mock(name: "Test"),
            notes: [Note.mock()],
            tasks: [],
            userQuery: "help me plan"
        )

        XCTAssertTrue(prompt.contains("Things"))
    }
}
