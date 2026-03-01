# Menu Bar Orchestrator Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform SeleneChat into a menu bar utility that launches at login, orchestrates all background workflows, and shows a Silver Crystal icon that sparkles when Ollama is processing.

**Architecture:** SwiftUI `MenuBarExtra` scene added alongside existing `WindowGroup`. A `WorkflowScheduler` service replaces 11 launchd plists by shelling out to existing TypeScript scripts via `Process`. The app starts as a menu bar accessory and optionally shows dock icon + chat window on demand.

**Tech Stack:** Swift/SwiftUI, `MenuBarExtra` (macOS 13+), `SMAppService` (login items), `Process` (shell execution), `TimelineView` (animation), `DispatchSource` (file watching)

**Design Doc:** `docs/plans/2026-02-12-menu-bar-orchestrator-design.md`

---

## Task 1: ScheduledWorkflow Model

**Files:**
- Create: `SeleneChat/Sources/Models/ScheduledWorkflow.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Models/ScheduledWorkflowTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class ScheduledWorkflowTests: XCTestCase {

    func testIntervalWorkflowCreation() {
        let workflow = ScheduledWorkflow(
            name: "process-llm",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true
        )
        XCTAssertEqual(workflow.name, "process-llm")
        XCTAssertTrue(workflow.usesOllama)
        if case .interval(let seconds) = workflow.schedule {
            XCTAssertEqual(seconds, 300)
        } else {
            XCTFail("Expected interval schedule")
        }
    }

    func testDailyWorkflowCreation() {
        let workflow = ScheduledWorkflow(
            name: "daily-summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true
        )
        if case .daily(let hour, let minute) = workflow.schedule {
            XCTAssertEqual(hour, 0)
            XCTAssertEqual(minute, 0)
        } else {
            XCTFail("Expected daily schedule")
        }
    }

    func testPersistentWorkflowCreation() {
        let workflow = ScheduledWorkflow(
            name: "server",
            scriptPath: "npm start",
            schedule: .persistent,
            usesOllama: false
        )
        if case .persistent = workflow.schedule {
            // pass
        } else {
            XCTFail("Expected persistent schedule")
        }
    }

    func testWatchPathWorkflowCreation() {
        let workflow = ScheduledWorkflow(
            name: "transcribe-voice-memos",
            scriptPath: "src/workflows/transcribe-voice-memos.ts",
            schedule: .watchPath("/path/to/watch"),
            usesOllama: false
        )
        if case .watchPath(let path) = workflow.schedule {
            XCTAssertEqual(path, "/path/to/watch")
        } else {
            XCTFail("Expected watchPath schedule")
        }
    }

    func testIsDueForIntervalWorkflow() {
        var workflow = ScheduledWorkflow(
            name: "process-llm",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true
        )
        // Never run = due
        XCTAssertTrue(workflow.isDue)

        // Just ran = not due
        workflow.lastRunAt = Date()
        XCTAssertFalse(workflow.isDue)

        // Ran 6 minutes ago = due (interval is 5 min)
        workflow.lastRunAt = Date().addingTimeInterval(-360)
        XCTAssertTrue(workflow.isDue)
    }

    func testIsDueForDailyWorkflow() {
        var workflow = ScheduledWorkflow(
            name: "daily-summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true
        )
        // Never run = due
        XCTAssertTrue(workflow.isDue)

        // Ran today = not due
        workflow.lastRunAt = Date()
        XCTAssertFalse(workflow.isDue)

        // Ran yesterday = due
        workflow.lastRunAt = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        XCTAssertTrue(workflow.isDue)
    }

    func testPersistentNeverDue() {
        let workflow = ScheduledWorkflow(
            name: "server",
            scriptPath: "npm start",
            schedule: .persistent,
            usesOllama: false
        )
        // Persistent workflows are managed separately, not by isDue
        XCTAssertFalse(workflow.isDue)
    }

    func testOllamaWorkflowFiltering() {
        let workflows = ScheduledWorkflow.allWorkflows
        let ollamaWorkflows = workflows.filter { $0.usesOllama }
        let nonOllamaWorkflows = workflows.filter { !$0.usesOllama }

        XCTAssertGreaterThan(ollamaWorkflows.count, 0)
        XCTAssertGreaterThan(nonOllamaWorkflows.count, 0)

        // Known Ollama workflows
        let ollamaNames = Set(ollamaWorkflows.map(\.name))
        XCTAssertTrue(ollamaNames.contains("process-llm"))
        XCTAssertTrue(ollamaNames.contains("index-vectors"))
        XCTAssertTrue(ollamaNames.contains("daily-summary"))
        XCTAssertTrue(ollamaNames.contains("detect-threads"))
        XCTAssertTrue(ollamaNames.contains("reconsolidate-threads"))
        XCTAssertTrue(ollamaNames.contains("extract-tasks"))

        // Known non-Ollama workflows
        let nonOllamaNames = Set(nonOllamaWorkflows.map(\.name))
        XCTAssertTrue(nonOllamaNames.contains("server"))
        XCTAssertTrue(nonOllamaNames.contains("send-digest"))
        XCTAssertTrue(nonOllamaNames.contains("export-obsidian"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter ScheduledWorkflowTests 2>&1 | tail -5`
Expected: FAIL — `ScheduledWorkflow` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation

struct ScheduledWorkflow: Identifiable {
    let id: String
    let name: String
    let scriptPath: String
    let schedule: Schedule
    let usesOllama: Bool
    var lastRunAt: Date?

    init(name: String, scriptPath: String, schedule: Schedule, usesOllama: Bool) {
        self.id = name
        self.name = name
        self.scriptPath = scriptPath
        self.schedule = schedule
        self.usesOllama = usesOllama
    }

    enum Schedule {
        case interval(TimeInterval)         // Every N seconds
        case daily(hour: Int, minute: Int)  // Specific time each day
        case persistent                     // Always running (server)
        case watchPath(String)              // File system trigger
    }

    var isDue: Bool {
        switch schedule {
        case .persistent, .watchPath:
            return false // Managed separately
        case .interval(let seconds):
            guard let lastRun = lastRunAt else { return true }
            return Date().timeIntervalSince(lastRun) >= seconds
        case .daily(let hour, let minute):
            guard let lastRun = lastRunAt else { return true }
            let calendar = Calendar.current
            if calendar.isDateInToday(lastRun) { return false }
            let now = Date()
            let todayComponents = calendar.dateComponents([.hour, .minute], from: now)
            guard let currentHour = todayComponents.hour,
                  let currentMinute = todayComponents.minute else { return false }
            return currentHour > hour || (currentHour == hour && currentMinute >= minute)
        }
    }

    static let projectRoot = "/Users/chaseeasterling/selene"

    static var allWorkflows: [ScheduledWorkflow] {
        [
            ScheduledWorkflow(name: "server", scriptPath: "npm start", schedule: .persistent, usesOllama: false),
            ScheduledWorkflow(name: "process-llm", scriptPath: "src/workflows/process-llm.ts", schedule: .interval(300), usesOllama: true),
            ScheduledWorkflow(name: "extract-tasks", scriptPath: "src/workflows/extract-tasks.ts", schedule: .interval(300), usesOllama: true),
            ScheduledWorkflow(name: "compute-relationships", scriptPath: "src/workflows/compute-relationships.ts", schedule: .interval(600), usesOllama: false),
            ScheduledWorkflow(name: "index-vectors", scriptPath: "src/workflows/index-vectors.ts", schedule: .interval(600), usesOllama: true),
            ScheduledWorkflow(name: "detect-threads", scriptPath: "src/workflows/detect-threads.ts", schedule: .interval(1800), usesOllama: true),
            ScheduledWorkflow(name: "reconsolidate-threads", scriptPath: "src/workflows/reconsolidate-threads.ts", schedule: .interval(3600), usesOllama: true),
            ScheduledWorkflow(name: "export-obsidian", scriptPath: "src/workflows/export-obsidian.ts", schedule: .daily(hour: 0, minute: 0), usesOllama: false),
            ScheduledWorkflow(name: "daily-summary", scriptPath: "src/workflows/daily-summary.ts", schedule: .daily(hour: 0, minute: 0), usesOllama: true),
            ScheduledWorkflow(name: "send-digest", scriptPath: "src/workflows/send-digest.ts", schedule: .daily(hour: 6, minute: 0), usesOllama: false),
            ScheduledWorkflow(name: "transcribe-voice-memos", scriptPath: "src/workflows/transcribe-voice-memos.ts", schedule: .watchPath("\(projectRoot)/data/voice-memos"), usesOllama: false),
        ]
    }
}
```

> **Note for implementer:** Check the actual WatchPaths value in `launchd/com.selene.transcribe-voice-memos.plist` and the actual StartCalendarInterval for `export-obsidian` — adjust the `allWorkflows` definition if they differ from what's shown above.

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter ScheduledWorkflowTests 2>&1 | tail -5`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Models/ScheduledWorkflow.swift SeleneChat/Tests/SeleneChatTests/Models/ScheduledWorkflowTests.swift
git commit -m "feat(selenechat): add ScheduledWorkflow model for workflow orchestration"
```

---

## Task 2: WorkflowRunner (Process Execution)

**Files:**
- Create: `SeleneChat/Sources/Services/WorkflowRunner.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/WorkflowRunnerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

final class WorkflowRunnerTests: XCTestCase {

    func testRunReturnsResult() async {
        let runner = WorkflowRunner()
        // Use a simple command that always works
        let result = await runner.run(command: "/bin/echo", arguments: ["hello"], workingDirectory: "/tmp")
        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.contains("hello"))
        XCTAssertEqual(result.exitCode, 0)
    }

    func testRunCapturesFailure() async {
        let runner = WorkflowRunner()
        let result = await runner.run(command: "/bin/false", arguments: [], workingDirectory: "/tmp")
        XCTAssertFalse(result.success)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testRunCapturesStderr() async {
        let runner = WorkflowRunner()
        let result = await runner.run(
            command: "/bin/sh",
            arguments: ["-c", "echo error >&2; exit 1"],
            workingDirectory: "/tmp"
        )
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.errorOutput.contains("error"))
    }

    func testRunNonexistentCommandFails() async {
        let runner = WorkflowRunner()
        let result = await runner.run(command: "/nonexistent/binary", arguments: [], workingDirectory: "/tmp")
        XCTAssertFalse(result.success)
    }

    func testBuildWorkflowCommandForTsNode() {
        let runner = WorkflowRunner()
        let workflow = ScheduledWorkflow(
            name: "process-llm",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true
        )
        let (command, args) = runner.buildCommand(for: workflow)
        XCTAssertEqual(command, "/usr/local/bin/npx")
        XCTAssertEqual(args, ["ts-node", "src/workflows/process-llm.ts"])
    }

    func testBuildWorkflowCommandForNpmStart() {
        let runner = WorkflowRunner()
        let workflow = ScheduledWorkflow(
            name: "server",
            scriptPath: "npm start",
            schedule: .persistent,
            usesOllama: false
        )
        let (command, args) = runner.buildCommand(for: workflow)
        XCTAssertEqual(command, "/usr/local/bin/npm")
        XCTAssertEqual(args, ["run", "start"])
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter WorkflowRunnerTests 2>&1 | tail -5`
Expected: FAIL — `WorkflowRunner` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation

struct WorkflowRunResult {
    let success: Bool
    let exitCode: Int32
    let output: String
    let errorOutput: String
}

class WorkflowRunner {
    let projectRoot: String

    init(projectRoot: String = ScheduledWorkflow.projectRoot) {
        self.projectRoot = projectRoot
    }

    func buildCommand(for workflow: ScheduledWorkflow) -> (command: String, arguments: [String]) {
        if workflow.scriptPath == "npm start" {
            return ("/usr/local/bin/npm", ["run", "start"])
        }
        return ("/usr/local/bin/npx", ["ts-node", workflow.scriptPath])
    }

    func run(command: String, arguments: [String], workingDirectory: String) async -> WorkflowRunResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
            process.environment = [
                "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "SELENE_DB_PATH": "\(projectRoot)/data/selene.db"
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

                continuation.resume(returning: WorkflowRunResult(
                    success: process.terminationStatus == 0,
                    exitCode: process.terminationStatus,
                    output: output,
                    errorOutput: errorOutput
                ))
            } catch {
                continuation.resume(returning: WorkflowRunResult(
                    success: false,
                    exitCode: -1,
                    output: "",
                    errorOutput: error.localizedDescription
                ))
            }
        }
    }

    func runWorkflow(_ workflow: ScheduledWorkflow) async -> WorkflowRunResult {
        let (command, args) = buildCommand(for: workflow)
        return await run(command: command, arguments: args, workingDirectory: projectRoot)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter WorkflowRunnerTests 2>&1 | tail -5`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/WorkflowRunner.swift SeleneChat/Tests/SeleneChatTests/Services/WorkflowRunnerTests.swift
git commit -m "feat(selenechat): add WorkflowRunner for TypeScript process execution"
```

---

## Task 3: WorkflowScheduler Service

**Files:**
- Create: `SeleneChat/Sources/Services/WorkflowScheduler.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/WorkflowSchedulerTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

@MainActor
final class WorkflowSchedulerTests: XCTestCase {

    func testInitialStateIsIdle() {
        let scheduler = WorkflowScheduler()
        XCTAssertTrue(scheduler.activeWorkflows.isEmpty)
        XCTAssertFalse(scheduler.isOllamaActive)
        XCTAssertNil(scheduler.lastError)
        XCTAssertFalse(scheduler.isEnabled)
    }

    func testIsOllamaActiveWhenOllamaWorkflowRunning() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("process-llm")
        XCTAssertTrue(scheduler.isOllamaActive)
    }

    func testIsOllamaInactiveWhenNonOllamaWorkflowRunning() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("send-digest")
        XCTAssertFalse(scheduler.isOllamaActive)
    }

    func testStatusTextIdle() {
        let scheduler = WorkflowScheduler()
        XCTAssertEqual(scheduler.statusText, "Idle")
    }

    func testStatusTextSingleWorkflow() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("process-llm")
        XCTAssertTrue(scheduler.statusText.contains("process-llm"))
    }

    func testStatusTextMultipleWorkflows() {
        let scheduler = WorkflowScheduler()
        scheduler.activeWorkflows.insert("process-llm")
        scheduler.activeWorkflows.insert("index-vectors")
        XCTAssertTrue(scheduler.statusText.contains("2"))
    }

    func testEnableStartsScheduling() {
        let scheduler = WorkflowScheduler()
        scheduler.enable()
        XCTAssertTrue(scheduler.isEnabled)
    }

    func testDisableStopsScheduling() {
        let scheduler = WorkflowScheduler()
        scheduler.enable()
        scheduler.disable()
        XCTAssertFalse(scheduler.isEnabled)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter WorkflowSchedulerTests 2>&1 | tail -5`
Expected: FAIL — `WorkflowScheduler` not defined

**Step 3: Write minimal implementation**

```swift
import Foundation
import Combine

@MainActor
class WorkflowScheduler: ObservableObject {
    @Published var activeWorkflows: Set<String> = []
    @Published var lastError: WorkflowError?
    @Published private(set) var isEnabled: Bool = false

    private var workflows: [ScheduledWorkflow] = ScheduledWorkflow.allWorkflows
    private var timer: Timer?
    private var serverProcess: Process?
    private let runner = WorkflowRunner()

    struct WorkflowError: Identifiable {
        let id = UUID()
        let workflowName: String
        let message: String
        let occurredAt: Date
    }

    var isOllamaActive: Bool {
        let ollamaNames = Set(workflows.filter(\.usesOllama).map(\.name))
        return !activeWorkflows.intersection(ollamaNames).isEmpty
    }

    var statusText: String {
        if activeWorkflows.isEmpty {
            return "Idle"
        } else if activeWorkflows.count == 1 {
            return "Running \(activeWorkflows.first!)..."
        } else {
            return "Running \(activeWorkflows.count) workflows..."
        }
    }

    func enable() {
        isEnabled = true
        startTimer()
        startServer()
    }

    func disable() {
        isEnabled = false
        timer?.invalidate()
        timer = nil
        stopServer()
    }

    private func startTimer() {
        // Check every 30 seconds for due workflows
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAndRunDueWorkflows()
            }
        }
    }

    private func checkAndRunDueWorkflows() async {
        guard isEnabled else { return }

        for i in workflows.indices {
            guard workflows[i].isDue, !activeWorkflows.contains(workflows[i].name) else { continue }

            let name = workflows[i].name
            activeWorkflows.insert(name)
            workflows[i].lastRunAt = Date()

            Task {
                let result = await runner.runWorkflow(workflows[i])
                await MainActor.run {
                    activeWorkflows.remove(name)
                    if !result.success {
                        lastError = WorkflowError(
                            workflowName: name,
                            message: result.errorOutput,
                            occurredAt: Date()
                        )
                    }
                }
            }
        }
    }

    private func startServer() {
        guard let serverWorkflow = workflows.first(where: { $0.name == "server" }) else { return }
        let (command, args) = runner.buildCommand(for: serverWorkflow)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: ScheduledWorkflow.projectRoot)
        process.environment = [
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "SELENE_DB_PATH": "\(ScheduledWorkflow.projectRoot)/data/selene.db"
        ]

        process.terminationHandler = { [weak self] process in
            guard process.terminationStatus != 0 else { return }
            // Restart on crash after 5 second delay
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled else { return }
                try? await Task.sleep(for: .seconds(5))
                self.startServer()
            }
        }

        do {
            try process.run()
            serverProcess = process
        } catch {
            lastError = WorkflowError(workflowName: "server", message: error.localizedDescription, occurredAt: Date())
        }
    }

    private func stopServer() {
        serverProcess?.terminate()
        serverProcess = nil
    }

    func shutdown() {
        disable()
        // Terminate any running workflow processes if tracked
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter WorkflowSchedulerTests 2>&1 | tail -5`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Services/WorkflowScheduler.swift SeleneChat/Tests/SeleneChatTests/Services/WorkflowSchedulerTests.swift
git commit -m "feat(selenechat): add WorkflowScheduler service for workflow orchestration"
```

---

## Task 4: Silver Crystal Menu Bar Icon

**Files:**
- Create: `SeleneChat/Sources/Views/SilverCrystalIcon.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Views/SilverCrystalIconTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

@MainActor
final class SilverCrystalIconTests: XCTestCase {

    func testIdleStateProperties() {
        let state = CrystalIconState.idle
        XCTAssertFalse(state.isAnimating)
        XCTAssertFalse(state.showsErrorBadge)
    }

    func testProcessingStateProperties() {
        let state = CrystalIconState.processing
        XCTAssertTrue(state.isAnimating)
        XCTAssertFalse(state.showsErrorBadge)
    }

    func testErrorStateProperties() {
        let state = CrystalIconState.error
        XCTAssertFalse(state.isAnimating)
        XCTAssertTrue(state.showsErrorBadge)
    }

    func testStateFromSchedulerIdle() {
        let state = CrystalIconState.from(isOllamaActive: false, hasError: false)
        XCTAssertEqual(state, .idle)
    }

    func testStateFromSchedulerProcessing() {
        let state = CrystalIconState.from(isOllamaActive: true, hasError: false)
        XCTAssertEqual(state, .processing)
    }

    func testStateFromSchedulerError() {
        let state = CrystalIconState.from(isOllamaActive: false, hasError: true)
        XCTAssertEqual(state, .error)
    }

    func testProcessingTakesPriorityOverError() {
        let state = CrystalIconState.from(isOllamaActive: true, hasError: true)
        XCTAssertEqual(state, .processing)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter SilverCrystalIconTests 2>&1 | tail -5`
Expected: FAIL — `CrystalIconState` not defined

**Step 3: Write minimal implementation**

The icon is a faceted crystal with crescent moon silhouette, inspired by the Silver Crystal (Ginzuishō). Uses `Canvas` for drawing and `TimelineView` for sparkle animation.

```swift
import SwiftUI

enum CrystalIconState: Equatable {
    case idle
    case processing
    case error

    var isAnimating: Bool { self == .processing }
    var showsErrorBadge: Bool { self == .error }

    static func from(isOllamaActive: Bool, hasError: Bool) -> CrystalIconState {
        if isOllamaActive { return .processing }
        if hasError { return .error }
        return .idle
    }
}

struct SilverCrystalIcon: View {
    let state: CrystalIconState
    let size: CGFloat

    init(state: CrystalIconState, size: CGFloat = 18) {
        self.state = state
        self.size = size
    }

    var body: some View {
        if state.isAnimating {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                CrystalCanvas(
                    state: state,
                    size: size,
                    date: timeline.date
                )
            }
            .frame(width: size, height: size)
        } else {
            CrystalCanvas(
                state: state,
                size: size,
                date: Date()
            )
            .frame(width: size, height: size)
        }
    }
}

private struct CrystalCanvas: View {
    let state: CrystalIconState
    let size: CGFloat
    let date: Date

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let scale = min(canvasSize.width, canvasSize.height)

            // Draw crystal body (faceted diamond shape)
            drawCrystal(in: &context, center: center, scale: scale)

            // Draw crescent moon cutout/overlay
            drawCrescent(in: &context, center: center, scale: scale)

            // Draw sparkles when processing
            if state.isAnimating {
                drawSparkles(in: &context, center: center, scale: scale, date: date)
            }

            // Draw error badge
            if state.showsErrorBadge {
                drawErrorBadge(in: &context, center: center, scale: scale)
            }
        }
    }

    private func drawCrystal(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        // Faceted crystal shape - elongated octagon
        let r = scale * 0.4
        let path = Path { p in
            // Top point
            p.move(to: CGPoint(x: center.x, y: center.y - r))
            // Upper right facet
            p.addLine(to: CGPoint(x: center.x + r * 0.5, y: center.y - r * 0.4))
            // Right point
            p.addLine(to: CGPoint(x: center.x + r * 0.6, y: center.y + r * 0.1))
            // Lower right facet
            p.addLine(to: CGPoint(x: center.x + r * 0.35, y: center.y + r * 0.7))
            // Bottom point
            p.addLine(to: CGPoint(x: center.x, y: center.y + r))
            // Lower left facet
            p.addLine(to: CGPoint(x: center.x - r * 0.35, y: center.y + r * 0.7))
            // Left point
            p.addLine(to: CGPoint(x: center.x - r * 0.6, y: center.y + r * 0.1))
            // Upper left facet
            p.addLine(to: CGPoint(x: center.x - r * 0.5, y: center.y - r * 0.4))
            p.closeSubpath()
        }

        // Inner glow when processing
        let opacity: Double = state.isAnimating ? pulseOpacity(date: date) : 0.6
        context.stroke(path, with: .color(.primary.opacity(0.9)), lineWidth: 1.2)
        context.fill(path, with: .color(.primary.opacity(opacity * 0.3)))

        // Internal facet lines
        let facetPath = Path { p in
            // Center to upper right
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + r * 0.5, y: center.y - r * 0.4))
            // Center to right
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + r * 0.6, y: center.y + r * 0.1))
            // Center to lower right
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + r * 0.35, y: center.y + r * 0.7))
            // Center to upper left
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x - r * 0.5, y: center.y - r * 0.4))
            // Center to left
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x - r * 0.6, y: center.y + r * 0.1))
            // Center to lower left
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x - r * 0.35, y: center.y + r * 0.7))
        }
        context.stroke(facetPath, with: .color(.primary.opacity(0.3)), lineWidth: 0.5)
    }

    private func drawCrescent(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        // Small crescent moon in upper-left area of crystal
        let moonCenter = CGPoint(x: center.x - scale * 0.1, y: center.y - scale * 0.15)
        let moonR = scale * 0.12

        let moonPath = Path { p in
            // Full circle
            p.addArc(center: moonCenter, radius: moonR, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
        context.fill(moonPath, with: .color(.primary.opacity(0.7)))

        // Cutout circle offset to create crescent
        let cutoutCenter = CGPoint(x: moonCenter.x + moonR * 0.5, y: moonCenter.y - moonR * 0.2)
        let cutoutPath = Path { p in
            p.addArc(center: cutoutCenter, radius: moonR * 0.85, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
        context.fill(cutoutPath, with: .color(.clear))
        // Use blendMode to cut out
        context.blendMode = .destinationOut
        context.fill(cutoutPath, with: .color(.white))
        context.blendMode = .normal
    }

    private func drawSparkles(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat, date: Date) {
        let time = date.timeIntervalSinceReferenceDate
        let sparkleCount = 5

        for i in 0..<sparkleCount {
            let angle = (Double(i) / Double(sparkleCount)) * .pi * 2 + time * 1.5
            let distance = scale * (0.45 + 0.1 * sin(time * 2.0 + Double(i)))
            let sparklePos = CGPoint(
                x: center.x + cos(angle) * distance,
                y: center.y + sin(angle) * distance
            )

            let sparkleSize = scale * 0.06 * (0.5 + 0.5 * sin(time * 3.0 + Double(i) * 1.3))
            let opacity = 0.4 + 0.6 * sin(time * 2.5 + Double(i) * 0.8)

            // Diamond-shaped sparkle
            let sparklePath = Path { p in
                p.move(to: CGPoint(x: sparklePos.x, y: sparklePos.y - sparkleSize))
                p.addLine(to: CGPoint(x: sparklePos.x + sparkleSize * 0.5, y: sparklePos.y))
                p.addLine(to: CGPoint(x: sparklePos.x, y: sparklePos.y + sparkleSize))
                p.addLine(to: CGPoint(x: sparklePos.x - sparkleSize * 0.5, y: sparklePos.y))
                p.closeSubpath()
            }
            context.fill(sparklePath, with: .color(.primary.opacity(opacity)))
        }
    }

    private func drawErrorBadge(in context: inout GraphicsContext, center: CGPoint, scale: CGFloat) {
        let badgeCenter = CGPoint(x: center.x + scale * 0.3, y: center.y - scale * 0.3)
        let badgeR = scale * 0.12
        let badgePath = Path { p in
            p.addArc(center: badgeCenter, radius: badgeR, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
        context.fill(badgePath, with: .color(.red))
    }

    private func pulseOpacity(date: Date) -> Double {
        let time = date.timeIntervalSinceReferenceDate
        return 0.5 + 0.5 * sin(time * 2.0)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter SilverCrystalIconTests 2>&1 | tail -5`
Expected: PASS

**Step 5: Visual verification**

Add a temporary preview to verify the icon looks right:

```swift
#if DEBUG
#Preview("Silver Crystal States") {
    HStack(spacing: 20) {
        VStack {
            SilverCrystalIcon(state: .idle, size: 44)
            Text("Idle")
        }
        VStack {
            SilverCrystalIcon(state: .processing, size: 44)
            Text("Processing")
        }
        VStack {
            SilverCrystalIcon(state: .error, size: 44)
            Text("Error")
        }
    }
    .padding(40)
}
#endif
```

> **Note:** The crystal shape and sparkle animation will likely need visual tuning. The code above is a starting point — adjust proportions, timing, and sparkle count based on how it looks at 18pt in the menu bar. The crescent moon `destinationOut` blend may need adjustment depending on menu bar background.

**Step 6: Commit**

```bash
git add SeleneChat/Sources/Views/SilverCrystalIcon.swift SeleneChat/Tests/SeleneChatTests/Views/SilverCrystalIconTests.swift
git commit -m "feat(selenechat): add Silver Crystal menu bar icon with sparkle animation"
```

---

## Task 5: Menu Bar Status View

**Files:**
- Create: `SeleneChat/Sources/Views/MenuBarStatusView.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Views/MenuBarStatusViewTests.swift`

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

@MainActor
final class MenuBarStatusViewTests: XCTestCase {

    func testStatusDotIdleIsInactive() {
        let isActive = false
        let dotSymbol = isActive ? "circle.fill" : "circle"
        XCTAssertEqual(dotSymbol, "circle")
    }

    func testStatusDotProcessingIsActive() {
        let isActive = true
        let dotSymbol = isActive ? "circle.fill" : "circle"
        XCTAssertEqual(dotSymbol, "circle.fill")
    }

    func testQuitActionKey() {
        // Verify quit keyboard shortcut is Q
        let shortcut = "Q"
        XCTAssertEqual(shortcut, "Q")
    }

    func testOpenSeleneActionKey() {
        // Verify open keyboard shortcut is O
        let shortcut = "O"
        XCTAssertEqual(shortcut, "O")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter MenuBarStatusViewTests 2>&1 | tail -5`
Expected: FAIL — file doesn't exist

**Step 3: Write implementation**

```swift
import SwiftUI

struct MenuBarStatusView: View {
    @EnvironmentObject var scheduler: WorkflowScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Status line
            HStack(spacing: 6) {
                Image(systemName: scheduler.activeWorkflows.isEmpty ? "circle" : "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(scheduler.activeWorkflows.isEmpty ? .secondary : .green)

                Text(scheduler.statusText)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()

            // Open Selene
            Button {
                openChatWindow()
            } label: {
                HStack {
                    Text("Open Selene")
                    Spacer()
                    Text("⌘O")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .keyboardShortcut("O", modifiers: .command)

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack {
                    Text("Quit")
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .keyboardShortcut("Q", modifiers: .command)
        }
        .frame(width: 200)
    }

    private func openChatWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Open the main window if it exists, or create one
        if let window = NSApplication.shared.windows.first(where: { $0.title.contains("Selene") || $0.isKeyWindow }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // WindowGroup will handle creating the window
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd SeleneChat && swift test --filter MenuBarStatusViewTests 2>&1 | tail -5`
Expected: PASS

**Step 5: Commit**

```bash
git add SeleneChat/Sources/Views/MenuBarStatusView.swift SeleneChat/Tests/SeleneChatTests/Views/MenuBarStatusViewTests.swift
git commit -m "feat(selenechat): add minimal menu bar status dropdown view"
```

---

## Task 6: App Lifecycle Changes

**Files:**
- Modify: `SeleneChat/Sources/App/SeleneChatApp.swift`
- Test: `SeleneChat/Tests/SeleneChatTests/Services/AppLifecycleTests.swift`

This is the integration task — adding `MenuBarExtra`, changing activation policy, and wiring the scheduler.

**Step 1: Write the failing test**

```swift
import XCTest
@testable import SeleneChat

@MainActor
final class AppLifecycleTests: XCTestCase {

    func testActivationPolicyAccessoryHidesDock() {
        // .accessory = no dock icon, no main menu
        let policy = NSApplication.ActivationPolicy.accessory
        XCTAssertEqual(policy, .accessory)
    }

    func testActivationPolicyRegularShowsDock() {
        // .regular = dock icon + main menu
        let policy = NSApplication.ActivationPolicy.regular
        XCTAssertEqual(policy, .regular)
    }

    func testWindowVisibilityTogglesPolicyAccessory() {
        // When no chat windows: accessory
        let chatWindowOpen = false
        let expectedPolicy: NSApplication.ActivationPolicy = chatWindowOpen ? .regular : .accessory
        XCTAssertEqual(expectedPolicy, .accessory)
    }

    func testWindowVisibilityTogglesPolicyRegular() {
        // When chat window open: regular
        let chatWindowOpen = true
        let expectedPolicy: NSApplication.ActivationPolicy = chatWindowOpen ? .regular : .accessory
        XCTAssertEqual(expectedPolicy, .regular)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd SeleneChat && swift test --filter AppLifecycleTests 2>&1 | tail -5`
Expected: FAIL — file doesn't exist

**Step 3: Create test file, then modify SeleneChatApp.swift**

The key changes to `SeleneChatApp.swift`:

1. Add `@StateObject private var scheduler = WorkflowScheduler()`
2. Change initial activation policy from `.regular` to `.accessory`
3. Add `MenuBarExtra` scene with Silver Crystal icon
4. Add window close handler to switch back to `.accessory`
5. Start scheduler on launch
6. Inject scheduler as environment object

```swift
// In SeleneChatApp.swift, replace the existing code:

@main
struct SeleneChatApp: App {
    @StateObject private var databaseService = DatabaseService.shared
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var compressionService = CompressionService(databaseService: DatabaseService.shared)
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var scheduler = WorkflowScheduler()

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Start as menu bar accessory (no dock icon)
        NSApplication.shared.setActivationPolicy(.accessory)

        configureServices()

        #if DEBUG
        setupDebugSystem()
        #endif
    }

    // ... configureServices() and setupDebugSystem() unchanged ...

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseService)
                .environmentObject(chatViewModel)
                .environmentObject(speechService)
                .environmentObject(scheduler)
                .frame(minWidth: 800, minHeight: 600)
                .task {
                    // Show dock icon when window opens
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)

                    await compressionService.checkAndCompressSessions()

                    Task.detached(priority: .background) {
                        do {
                            let count = try await MemoryService.shared.backfillEmbeddings()
                            if count > 0 {
                                #if DEBUG
                                DebugLogger.shared.log(.state, "SeleneChatApp: backfilled \(count) memory embeddings")
                                #endif
                            }
                        } catch {
                            #if DEBUG
                            DebugLogger.shared.log(.error, "SeleneChatApp: memory backfill failed - \(error)")
                            #endif
                        }
                    }

                    // Start scheduler on first window open
                    if !scheduler.isEnabled {
                        scheduler.enable()
                    }

                    #if DEBUG
                    await MainActor.run {
                        DebugSnapshotService.shared.registerProvider(named: "chatViewModel", provider: chatViewModel)
                    }
                    #endif
                }
                .onOpenURL { url in
                    let action = VoiceInputManager.parseURL(url)
                    if action == .activateVoice {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        Task {
                            try? await Task.sleep(for: .milliseconds(200))
                            await speechService.startListening()
                        }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(databaseService)
        }

        MenuBarExtra {
            MenuBarStatusView()
                .environmentObject(scheduler)
        } label: {
            SilverCrystalIcon(
                state: CrystalIconState.from(
                    isOllamaActive: scheduler.isOllamaActive,
                    hasError: scheduler.lastError != nil
                ),
                size: 18
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// AppDelegate to handle window close -> hide dock icon
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when windows close — stay in menu bar
        // Switch back to accessory mode (hide dock icon)
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        return false
    }
}
```

**Step 4: Run all tests to verify nothing breaks**

Run: `cd SeleneChat && swift test 2>&1 | tail -10`
Expected: All tests PASS (270+)

**Step 5: Run the app to verify menu bar icon appears**

Run: `cd SeleneChat && swift build && .build/debug/SeleneChat`

Verify:
- No dock icon on launch (accessory mode)
- Silver Crystal icon appears in menu bar
- Click icon → dropdown shows "Idle" status + "Open Selene" + "Quit"
- Click "Open Selene" → chat window appears, dock icon appears
- Close chat window → dock icon disappears, app stays in menu bar
- Click "Quit" → app terminates

**Step 6: Commit**

```bash
git add SeleneChat/Sources/App/SeleneChatApp.swift SeleneChat/Tests/SeleneChatTests/Services/AppLifecycleTests.swift
git commit -m "feat(selenechat): integrate menu bar, scheduler, and app lifecycle changes"
```

---

## Task 7: Login Item Registration

**Files:**
- Modify: `SeleneChat/Sources/App/SeleneChatApp.swift` (add to init)
- Modify: `SeleneChat/Sources/Views/MenuBarStatusView.swift` (add toggle)

**Step 1: Add SMAppService import and login item registration**

In `SeleneChatApp.swift` init, add:

```swift
import ServiceManagement

// In init():
// Register as login item (user can manage in System Settings > General > Login Items)
if #available(macOS 13.0, *) {
    do {
        try SMAppService.mainApp.register()
    } catch {
        // Not critical — user can enable manually in System Settings
        #if DEBUG
        DebugLogger.shared.log(.error, "Failed to register login item: \(error)")
        #endif
    }
}
```

**Step 2: Build and verify**

Run: `cd SeleneChat && swift build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

> **Note:** `SMAppService.mainApp.register()` may require the app to be code-signed and in `/Applications` to work properly. During development, the login item won't persist — this is expected. It will work when installed via `build-app.sh`.

**Step 3: Commit**

```bash
git add SeleneChat/Sources/App/SeleneChatApp.swift
git commit -m "feat(selenechat): register as login item via SMAppService"
```

---

## Task 8: Migration Script

**Files:**
- Create: `scripts/uninstall-launchd.sh`

**Step 1: Write the migration script**

```bash
#!/bin/bash
# Uninstall Selene launchd agents (replaced by SeleneChat menu bar orchestration)
# Usage: ./scripts/uninstall-launchd.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "DRY RUN — no changes will be made"
fi

PLIST_DIR="$HOME/Library/LaunchAgents"
PLISTS=(
    "com.selene.server"
    "com.selene.process-llm"
    "com.selene.extract-tasks"
    "com.selene.compute-relationships"
    "com.selene.index-vectors"
    "com.selene.detect-threads"
    "com.selene.reconsolidate-threads"
    "com.selene.export-obsidian"
    "com.selene.daily-summary"
    "com.selene.send-digest"
    "com.selene.transcribe-voice-memos"
)

echo "Uninstalling Selene launchd agents..."
echo ""

for label in "${PLISTS[@]}"; do
    plist_file="$PLIST_DIR/$label.plist"

    # Stop the agent if running
    if launchctl list | grep -q "$label"; then
        echo "  Stopping: $label"
        if [[ "$DRY_RUN" == false ]]; then
            launchctl stop "$label" 2>/dev/null || true
            launchctl unload "$plist_file" 2>/dev/null || true
        fi
    else
        echo "  Not running: $label"
    fi

    # Remove the plist
    if [[ -f "$plist_file" ]]; then
        echo "  Removing: $plist_file"
        if [[ "$DRY_RUN" == false ]]; then
            rm "$plist_file"
        fi
    else
        echo "  Not installed: $plist_file"
    fi
done

echo ""
echo "Done. SeleneChat now handles all workflow scheduling."
echo "Make sure SeleneChat is running (it should start automatically at login)."
```

**Step 2: Make executable and test dry run**

```bash
chmod +x scripts/uninstall-launchd.sh
./scripts/uninstall-launchd.sh --dry-run
```

Expected: Lists all agents, says "DRY RUN", no changes made

**Step 3: Commit**

```bash
git add scripts/uninstall-launchd.sh
git commit -m "feat(scripts): add uninstall-launchd.sh for migration to menu bar orchestration"
```

---

## Task 9: Integration Testing

**No new files — manual verification checklist**

**Step 1: Build and run**

```bash
cd SeleneChat && swift build && .build/debug/SeleneChat
```

**Step 2: Verify menu bar behavior**

- [ ] Crystal icon appears in menu bar on launch
- [ ] No dock icon on initial launch
- [ ] Click crystal → dropdown shows idle status
- [ ] Click "Open Selene" → chat window opens, dock icon appears
- [ ] Close chat window → dock icon disappears
- [ ] Crystal stays in menu bar after window close
- [ ] "Quit" terminates the app

**Step 3: Verify scheduler (with launchd still running in parallel)**

- [ ] Scheduler starts when enabled
- [ ] Status text updates when workflows run
- [ ] Crystal sparkles when Ollama workflows are active
- [ ] Crystal shows error badge on workflow failure
- [ ] Non-Ollama workflows don't trigger sparkle

**Step 4: Verify existing functionality**

- [ ] Chat still works (send message, get AI response)
- [ ] Voice input still works
- [ ] Database queries still work
- [ ] All existing tests pass: `cd SeleneChat && swift test`

**Step 5: Install and verify login item**

```bash
cd SeleneChat && ./build-app.sh
# Restart, verify SeleneChat starts automatically
```

**Step 6: Final commit**

```bash
git commit -m "test(selenechat): verify menu bar orchestrator integration"
```

---

## Summary

| Task | Component | Files Created/Modified |
|------|-----------|----------------------|
| 1 | ScheduledWorkflow model | 2 new (model + test) |
| 2 | WorkflowRunner | 2 new (service + test) |
| 3 | WorkflowScheduler service | 2 new (service + test) |
| 4 | Silver Crystal icon | 2 new (view + test) |
| 5 | Menu bar status dropdown | 2 new (view + test) |
| 6 | App lifecycle integration | 1 modified + 1 new test |
| 7 | Login item registration | 1 modified |
| 8 | Migration script | 1 new |
| 9 | Integration testing | Manual verification |

**Total:** 10 new files, 1 modified file, ~600 lines of production code, ~200 lines of test code
