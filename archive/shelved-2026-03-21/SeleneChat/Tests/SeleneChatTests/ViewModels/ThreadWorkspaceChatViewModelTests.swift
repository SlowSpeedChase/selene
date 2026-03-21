import SeleneShared
import XCTest
@testable import SeleneChat

@MainActor
final class ThreadWorkspaceChatViewModelTests: XCTestCase {

    // MARK: - Initialization

    func testInitialState() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertTrue(vm.messages.isEmpty)
        XCTAssertFalse(vm.isProcessing)
        XCTAssertTrue(vm.pendingActions.isEmpty)
    }

    func testInitStoresThreadContext() {
        let thread = Thread.mock(name: "Voice Feature")
        let notes = [Note.mock(id: 1), Note.mock(id: 2)]
        let tasks = [ThreadTask.mock(thingsTaskId: "T-1")]

        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: notes,
            tasks: tasks
        )

        XCTAssertEqual(vm.thread.name, "Voice Feature")
        XCTAssertEqual(vm.notes.count, 2)
        XCTAssertEqual(vm.tasks.count, 1)
    }

    // MARK: - Action Extraction from Response

    func testProcessResponseExtractsActions() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        let responseWithActions = """
        Here are some next steps for your project.
        [ACTION: Write integration tests | ENERGY: medium | TIMEFRAME: this-week]
        [ACTION: Set up CI pipeline | ENERGY: high | TIMEFRAME: today]
        Let me know if you want to explore further.
        """

        vm.processResponse(responseWithActions)

        // Should extract 2 actions
        XCTAssertEqual(vm.pendingActions.count, 2)
        XCTAssertEqual(vm.pendingActions[0].description, "Write integration tests")
        XCTAssertEqual(vm.pendingActions[0].energy, .medium)
        XCTAssertEqual(vm.pendingActions[1].description, "Set up CI pipeline")
        XCTAssertEqual(vm.pendingActions[1].timeframe, .today)
    }

    func testProcessResponseAddsCleanedMessage() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        let responseWithActions = """
        Here are some steps.
        [ACTION: Do something | ENERGY: low | TIMEFRAME: someday]
        Let me know.
        """

        vm.processResponse(responseWithActions)

        // Should have one assistant message with actions removed
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages[0].role, .assistant)
        XCTAssertFalse(vm.messages[0].content.contains("[ACTION:"))
        XCTAssertTrue(vm.messages[0].content.contains("Here are some steps"))
        XCTAssertTrue(vm.messages[0].content.contains("Let me know"))
    }

    func testProcessResponseWithNoActions() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        vm.processResponse("Just a normal response with no actions.")

        XCTAssertTrue(vm.pendingActions.isEmpty)
        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages[0].content, "Just a normal response with no actions.")
    }

    // MARK: - Dismiss Actions

    func testDismissActionsClearsPending() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        // Simulate having pending actions
        vm.processResponse("[ACTION: Task 1 | ENERGY: high | TIMEFRAME: today]")
        XCTAssertEqual(vm.pendingActions.count, 1)

        vm.dismissActions()

        XCTAssertTrue(vm.pendingActions.isEmpty)
    }

    // MARK: - Add User Message

    func testAddUserMessage() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        vm.addUserMessage("What should I work on next?")

        XCTAssertEqual(vm.messages.count, 1)
        XCTAssertEqual(vm.messages[0].role, .user)
        XCTAssertEqual(vm.messages[0].content, "What should I work on next?")
        XCTAssertEqual(vm.messages[0].llmTier, .local)
    }

    // MARK: - Conversation History

    func testConversationHistoryBuildsFromMessages() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        // Build up a conversation
        vm.addUserMessage("First question")
        vm.processResponse("First answer")
        vm.addUserMessage("Follow-up question")
        vm.processResponse("Follow-up answer")

        let history = vm.buildConversationHistory()

        XCTAssertTrue(history.contains("First question"))
        XCTAssertTrue(history.contains("First answer"))
        XCTAssertTrue(history.contains("Follow-up question"))
        XCTAssertTrue(history.contains("Follow-up answer"))
    }

    // MARK: - Prompt Building

    func testFirstMessageUsesInitialPrompt() {
        let thread = Thread.mock(name: "Architecture Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: [ThreadTask.mock(title: "Existing task")]
        )

        let prompt = vm.buildPrompt(for: "What should I focus on?")

        // Initial prompt should include thread name and task context
        XCTAssertTrue(prompt.contains("Architecture Thread"))
        XCTAssertTrue(prompt.contains("Existing task"))
        XCTAssertTrue(prompt.contains("[ACTION:"))
    }

    func testSubsequentMessageUsesFollowUpPrompt() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        // Add prior conversation
        vm.addUserMessage("First question")
        vm.processResponse("First answer")

        let prompt = vm.buildPrompt(for: "Follow-up question")

        // Follow-up prompt should include conversation history
        XCTAssertTrue(prompt.contains("First question"))
        XCTAssertTrue(prompt.contains("First answer"))
        XCTAssertTrue(prompt.contains("Follow-up question"))
    }

    // MARK: - Multiple Action Rounds

    func testNewActionsReplacePreviousPending() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        // First response with actions
        vm.processResponse("[ACTION: Task A | ENERGY: high | TIMEFRAME: today]")
        XCTAssertEqual(vm.pendingActions.count, 1)
        XCTAssertEqual(vm.pendingActions[0].description, "Task A")

        // Second response with different actions - should replace
        vm.processResponse("[ACTION: Task B | ENERGY: low | TIMEFRAME: someday]")
        XCTAssertEqual(vm.pendingActions.count, 1)
        XCTAssertEqual(vm.pendingActions[0].description, "Task B")
    }

    // MARK: - Update Tasks

    func testUpdateTasksUpdatesContext() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(
            thread: thread,
            notes: [Note.mock()],
            tasks: []
        )

        XCTAssertTrue(vm.tasks.isEmpty)

        let newTasks = [
            ThreadTask.mock(thingsTaskId: "T-1", title: "New task")
        ]
        vm.updateTasks(newTasks)

        XCTAssertEqual(vm.tasks.count, 1)
        XCTAssertEqual(vm.tasks[0].title, "New task")
    }

    // MARK: - What's Next Routing

    func testBuildPromptUsesWhatsNextForMatchingQuery() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(thread: thread, notes: [], tasks: [])

        let prompt = vm.buildPrompt(for: "what's next?")
        XCTAssertTrue(prompt.contains("2-3"), "Should use what's next prompt")
    }

    func testBuildPromptUsesRegularForNonMatchingQuery() {
        let thread = Thread.mock(name: "Test Thread")
        let vm = ThreadWorkspaceChatViewModel(thread: thread, notes: [], tasks: [])

        let prompt = vm.buildPrompt(for: "break down the auth task")
        XCTAssertFalse(prompt.contains("recommend ONE specific task"),
                       "Should NOT use what's next prompt for regular queries")
    }

    // MARK: - Planning Detection Routing

    func testBuildPromptUsesPlanningPromptForPlanningQueries() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]
        let vm = ThreadWorkspaceChatViewModel(thread: thread, notes: notes, tasks: [])

        let prompt = vm.buildPrompt(for: "help me make a plan for this")

        XCTAssertTrue(
            prompt.contains("Do NOT jump to a full plan"),
            "Planning queries should use the dedicated planning prompt"
        )
    }

    func testBuildPromptUsesRegularPromptForNonPlanningQueries() {
        let thread = Thread.mock(name: "Test Thread")
        let notes = [Note.mock()]
        let vm = ThreadWorkspaceChatViewModel(thread: thread, notes: notes, tasks: [])

        let prompt = vm.buildPrompt(for: "tell me about this thread")

        XCTAssertFalse(
            prompt.contains("Do NOT jump to a full plan"),
            "Non-planning queries should NOT use the dedicated planning prompt"
        )
    }
}
