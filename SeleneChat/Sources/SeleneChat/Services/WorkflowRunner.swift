import SeleneShared
import Foundation

/// The result of executing a workflow or shell command.
struct WorkflowRunResult {
    /// Whether the process exited with code 0.
    let success: Bool
    /// The process exit code.
    let exitCode: Int32
    /// Captured standard output.
    let output: String
    /// Captured standard error.
    let errorOutput: String
}

/// Executes TypeScript workflow scripts by shelling out via `Process`.
///
/// Used by `WorkflowScheduler` to run Selene background workflows.
/// Each workflow is either a TypeScript script (run via `npx ts-node`)
/// or the server process (run via `npm run start`).
final class WorkflowRunner {

    /// The root directory of the selene project.
    let projectRoot: String

    /// Creates a runner targeting the given project root.
    ///
    /// - Parameter projectRoot: Path to the selene directory.
    ///   Defaults to `ScheduledWorkflow.projectRoot`.
    init(projectRoot: String = ScheduledWorkflow.projectRoot) {
        self.projectRoot = projectRoot
    }

    // MARK: - Build Command

    /// Converts a workflow into the shell command and arguments needed to run it.
    ///
    /// - The server workflow (`scriptPath == "npm start"`) uses `/usr/local/bin/npm run start`.
    /// - All other workflows use `/usr/local/bin/npx ts-node <scriptPath>`.
    ///
    /// - Parameter workflow: The workflow to build a command for.
    /// - Returns: A tuple of the executable path and its arguments.
    func buildCommand(for workflow: ScheduledWorkflow) -> (command: String, arguments: [String]) {
        return (command: "/usr/local/bin/npx", arguments: ["ts-node", workflow.scriptPath])
    }

    // MARK: - Run

    /// Executes a command as a child process, capturing stdout and stderr.
    ///
    /// - Parameters:
    ///   - command: Absolute path to the executable.
    ///   - arguments: Arguments to pass to the executable.
    ///   - workingDirectory: The working directory for the child process.
    /// - Returns: A `WorkflowRunResult` with captured output and exit status.
    func run(
        command: String,
        arguments: [String],
        workingDirectory: String
    ) async -> WorkflowRunResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            env["SELENE_DB_PATH"] = "\(projectRoot)/data/selene.db"
            env["SELENE_ENV"] = "production"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                let result = WorkflowRunResult(
                    success: false,
                    exitCode: -1,
                    output: "",
                    errorOutput: error.localizedDescription
                )
                continuation.resume(returning: result)
                return
            }

            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let output = String(data: stdoutData, encoding: .utf8) ?? ""
            let errorOutput = String(data: stderrData, encoding: .utf8) ?? ""
            let exitCode = process.terminationStatus

            let result = WorkflowRunResult(
                success: exitCode == 0,
                exitCode: exitCode,
                output: output,
                errorOutput: errorOutput
            )
            continuation.resume(returning: result)
        }
    }

    // MARK: - Run Workflow

    /// Convenience that builds the command for a workflow and executes it.
    ///
    /// - Parameter workflow: The workflow to run.
    /// - Returns: A `WorkflowRunResult` with captured output and exit status.
    func runWorkflow(_ workflow: ScheduledWorkflow) async -> WorkflowRunResult {
        let (command, arguments) = buildCommand(for: workflow)
        return await run(
            command: command,
            arguments: arguments,
            workingDirectory: projectRoot
        )
    }
}
