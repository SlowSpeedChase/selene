import SeleneShared
import Foundation

/// Schedules and runs Selene background TypeScript workflows, replacing launchd plists.
///
/// Maintains a timer that fires every 30 seconds, checks which workflows are due,
/// and launches them via `WorkflowRunner`. Also manages the Selene server as a
/// long-running child process, restarting it on crash with a 5-second delay.
@MainActor
class WorkflowScheduler: ObservableObject {

    // MARK: - WorkflowError

    /// Describes a failure that occurred while running a workflow.
    struct WorkflowError: Identifiable {
        let id: UUID
        let workflowName: String
        let message: String
        let occurredAt: Date
    }

    // MARK: - Published Properties

    /// Names of currently running workflows.
    @Published var activeWorkflows: Set<String> = []

    /// The most recent workflow error, if any.
    @Published var lastError: WorkflowError?

    /// Whether the scheduler is active (timer running, server managed).
    @Published private(set) var isEnabled: Bool = false

    // MARK: - Computed Properties

    /// True when any currently active workflow depends on Ollama.
    var isOllamaActive: Bool {
        let ollamaWorkflowNames = Set(
            ScheduledWorkflow.allWorkflows
                .filter(\.usesOllama)
                .map(\.name)
        )
        return !activeWorkflows.isDisjoint(with: ollamaWorkflowNames)
    }

    /// Human-readable description of current scheduler activity.
    var statusText: String {
        switch activeWorkflows.count {
        case 0:
            return "Idle"
        case 1:
            return "Running \(activeWorkflows.first!)..."
        default:
            return "Running \(activeWorkflows.count) workflows..."
        }
    }

    /// Snapshot of each workflow's current state, for display in the menu bar dropdown.
    var workflowSnapshots: [WorkflowSnapshot] {
        workflows.compactMap { wf in
            // Skip the persistent server entry — it's shown separately as the status line
            guard wf.schedule != .persistent else { return nil }
            return WorkflowSnapshot(
                name: wf.name,
                isRunning: activeWorkflows.contains(wf.name),
                lastRunAt: wf.lastRunAt,
                usesOllama: wf.usesOllama
            )
        }
    }

    /// Read-only snapshot of a workflow for UI display.
    struct WorkflowSnapshot: Identifiable {
        var id: String { name }
        let name: String
        let isRunning: Bool
        let lastRunAt: Date?
        let usesOllama: Bool
    }

    // MARK: - Private State

    /// Mutable copies of workflow definitions with `lastRunAt` tracking.
    private var workflows: [ScheduledWorkflow]

    /// The runner used to execute workflow processes.
    private let runner: WorkflowRunner

    /// Timer that fires every 30 seconds to check for due workflows.
    private var schedulerTimer: Timer?

    /// The server child process (long-running, persistent schedule).
    private var serverProcess: Process?

    /// Whether a server restart is currently pending (debounce).
    private var serverRestartPending: Bool = false

    // MARK: - Constants

    /// How often the scheduler checks for due workflows, in seconds.
    private static let tickInterval: TimeInterval = 30

    /// Delay before restarting a crashed server, in seconds.
    private static let serverRestartDelay: TimeInterval = 5

    // MARK: - Init

    init(runner: WorkflowRunner = WorkflowRunner()) {
        self.runner = runner
        self.workflows = ScheduledWorkflow.allWorkflows
    }

    // MARK: - Enable / Disable / Shutdown

    /// Activates the scheduler: starts the tick timer and launches the server.
    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        startTimer()
        startServer()
    }

    /// Deactivates the scheduler: stops the tick timer and terminates the server.
    func disable() {
        isEnabled = false
        stopTimer()
        stopServer()
    }

    /// Fully shuts down: disables the scheduler and clears all active workflow state.
    func shutdown() {
        disable()
        activeWorkflows.removeAll()
    }

    // MARK: - Timer

    /// Creates and schedules the 30-second tick timer.
    private func startTimer() {
        stopTimer()
        schedulerTimer = Timer.scheduledTimer(
            withTimeInterval: Self.tickInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    /// Invalidates and removes the tick timer.
    private func stopTimer() {
        schedulerTimer?.invalidate()
        schedulerTimer = nil
    }

    // MARK: - Tick (Scheduling Logic)

    /// Called every 30 seconds. Checks each workflow and launches any that are due.
    private func tick() {
        guard isEnabled else { return }

        for index in workflows.indices {
            let workflow = workflows[index]

            // Skip persistent/watchPath (managed separately) and already-running workflows
            guard workflow.isDue, !activeWorkflows.contains(workflow.name) else { continue }

            // Mark as running
            activeWorkflows.insert(workflow.name)
            workflows[index].lastRunAt = Date()

            // Launch asynchronously
            let workflowCopy = workflow
            Task { [weak self] in
                await self?.runWorkflow(workflowCopy)
            }
        }
    }

    // MARK: - Workflow Execution

    /// Runs a single workflow and updates state when it completes.
    private func runWorkflow(_ workflow: ScheduledWorkflow) async {
        let result = await runner.runWorkflow(workflow)

        // Back on MainActor (method is implicitly @MainActor via class)
        activeWorkflows.remove(workflow.name)

        if result.success {
            // Clear any previous error on successful run
            if lastError != nil { lastError = nil }
        } else {
            lastError = WorkflowError(
                id: UUID(),
                workflowName: workflow.name,
                message: result.errorOutput.isEmpty
                    ? "Exit code \(result.exitCode)"
                    : String(result.errorOutput.prefix(500)),
                occurredAt: Date()
            )
        }
    }

    // MARK: - Server Management

    /// Launches the Selene server as a long-running child process.
    /// If an orphaned server from a previous launch is already healthy, adopts it.
    private func startServer() {
        // Don't launch if already running
        if let existing = serverProcess, existing.isRunning { return }

        // Check if an orphaned server is already healthy on port 5678
        Task { [weak self] in
            if await Self.isServerHealthy() {
                await MainActor.run {
                    self?.lastError = nil
                }
                return
            }
            await MainActor.run {
                self?.launchServerProcess()
            }
        }
    }

    /// Returns true if the server at localhost:5678 responds to a health check.
    private static func isServerHealthy() async -> Bool {
        guard let url = URL(string: "http://localhost:5678/health") else { return false }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 2
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Actually spawns the server child process.
    private func launchServerProcess() {
        guard let serverWorkflow = workflows.first(where: { $0.schedule == .persistent }) else {
            return
        }

        let (command, arguments) = runner.buildCommand(for: serverWorkflow)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: runner.projectRoot)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["SELENE_DB_PATH"] = "\(runner.projectRoot)/data/selene.db"
        env["SELENE_ENV"] = "production"
        process.environment = env

        // Discard output (server logs to its own file)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Monitor for unexpected termination
        process.terminationHandler = { [weak self] terminatedProcess in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }

                // Server crashed -- schedule restart after delay
                if terminatedProcess.terminationStatus != 0, !self.serverRestartPending {
                    self.serverRestartPending = true
                    self.lastError = WorkflowError(
                        id: UUID(),
                        workflowName: "Selene Server",
                        message: "Server crashed (exit \(terminatedProcess.terminationStatus)), restarting in \(Int(Self.serverRestartDelay))s",
                        occurredAt: Date()
                    )

                    try? await Task.sleep(nanoseconds: UInt64(Self.serverRestartDelay * 1_000_000_000))
                    self.serverRestartPending = false
                    if self.isEnabled {
                        self.stopServer()
                        self.startServer()
                    }
                }
            }
        }

        do {
            try process.run()
            serverProcess = process
            lastError = nil
        } catch {
            lastError = WorkflowError(
                id: UUID(),
                workflowName: "Selene Server",
                message: "Failed to start server: \(error.localizedDescription)",
                occurredAt: Date()
            )
        }
    }

    /// Terminates the server child process if running.
    private func stopServer() {
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
        serverProcess = nil
    }
}
