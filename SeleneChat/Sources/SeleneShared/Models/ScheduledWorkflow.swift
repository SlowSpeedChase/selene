import Foundation

/// A background workflow with its scheduling configuration.
///
/// Defines each Selene TypeScript workflow that runs in the background,
/// including how often it should run and whether it depends on Ollama.
/// Used by `WorkflowScheduler` to determine when to launch each workflow.
public struct ScheduledWorkflow: Identifiable {
    public let id: String
    public let name: String
    public let scriptPath: String
    public let schedule: Schedule
    public let usesOllama: Bool
    public var lastRunAt: Date?

    public init(
        id: String,
        name: String,
        scriptPath: String,
        schedule: Schedule,
        usesOllama: Bool,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.scriptPath = scriptPath
        self.schedule = schedule
        self.usesOllama = usesOllama
        self.lastRunAt = lastRunAt
    }

    /// How a workflow is scheduled to run.
    public enum Schedule: Equatable {
        /// Run at a fixed interval (in seconds) from the last run.
        case interval(TimeInterval)
        /// Run once per day at the specified hour and minute.
        case daily(hour: Int, minute: Int)
        /// Always running (long-lived process, not scheduled).
        case persistent
        /// Triggered by filesystem changes at the given path.
        case watchPath(String)
    }

    /// Whether this workflow should run now based on its schedule and last run time.
    ///
    /// Persistent and watchPath workflows are never "due" because they are
    /// managed separately (kept alive or triggered by filesystem events).
    public var isDue: Bool {
        switch schedule {
        case .persistent, .watchPath:
            return false

        case .interval(let seconds):
            guard let lastRun = lastRunAt else { return true }
            return Date().timeIntervalSince(lastRun) >= seconds

        case .daily:
            guard let lastRun = lastRunAt else { return true }
            return !Calendar.current.isDateInToday(lastRun)
        }
    }

    // MARK: - Project Root

    /// The root directory of the selene project.
    ///
    /// Always returns the canonical path (`~/selene`), even when running
    /// from a worktree. Workflows execute against the main project directory.
    public static var projectRoot: String {
        #if os(iOS)
        let home = NSHomeDirectory()
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #endif
        return "\(home)/selene"
    }

    // MARK: - All Workflows

    /// All Selene background workflows, matching the launchd agent configuration.
    public static let allWorkflows: [ScheduledWorkflow] = [
        ScheduledWorkflow(
            id: "server",
            name: "Selene Server",
            scriptPath: "src/server.ts",
            schedule: .persistent,
            usesOllama: false
        ),
        ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true
        ),
        ScheduledWorkflow(
            id: "extract-tasks",
            name: "Extract Tasks",
            scriptPath: "src/workflows/extract-tasks.ts",
            schedule: .interval(300),
            usesOllama: true
        ),
        ScheduledWorkflow(
            id: "compute-relationships",
            name: "Compute Relationships",
            scriptPath: "src/workflows/compute-relationships.ts",
            schedule: .interval(600),
            usesOllama: false
        ),
        ScheduledWorkflow(
            id: "index-vectors",
            name: "Index Vectors",
            scriptPath: "src/workflows/index-vectors.ts",
            schedule: .interval(600),
            usesOllama: true
        ),
        ScheduledWorkflow(
            id: "detect-threads",
            name: "Detect Threads",
            scriptPath: "src/workflows/detect-threads.ts",
            schedule: .interval(1800),
            usesOllama: true
        ),
        ScheduledWorkflow(
            id: "reconsolidate-threads",
            name: "Reconsolidate Threads",
            scriptPath: "src/workflows/reconsolidate-threads.ts",
            schedule: .interval(3600),
            usesOllama: true
        ),
        ScheduledWorkflow(
            id: "export-obsidian",
            name: "Export Obsidian",
            scriptPath: "src/workflows/export-obsidian.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: false
        ),
        ScheduledWorkflow(
            id: "daily-summary",
            name: "Daily Summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true
        ),
        ScheduledWorkflow(
            id: "send-digest",
            name: "Send Digest",
            scriptPath: "src/workflows/send-digest.ts",
            schedule: .daily(hour: 6, minute: 0),
            usesOllama: false
        ),
        ScheduledWorkflow(
            id: "transcribe-voice-memos",
            name: "Transcribe Voice Memos",
            scriptPath: "src/workflows/transcribe-voice-memos.ts",
            schedule: .watchPath({
                #if os(iOS)
                return NSHomeDirectory() + "/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
                #else
                return FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"
                #endif
            }()),
            usesOllama: false
        ),
    ]
}

#if DEBUG
extension ScheduledWorkflow {
    public static func mock(
        id: String = "test-workflow",
        name: String = "Test Workflow",
        scriptPath: String = "src/workflows/test.ts",
        schedule: Schedule = .interval(300),
        usesOllama: Bool = false,
        lastRunAt: Date? = nil
    ) -> ScheduledWorkflow {
        ScheduledWorkflow(
            id: id,
            name: name,
            scriptPath: scriptPath,
            schedule: schedule,
            usesOllama: usesOllama,
            lastRunAt: lastRunAt
        )
    }
}
#endif
