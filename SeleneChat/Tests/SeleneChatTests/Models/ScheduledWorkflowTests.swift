import SeleneShared
import XCTest
@testable import SeleneChat

final class ScheduledWorkflowTests: XCTestCase {

    // MARK: - Schedule Enum

    func testIntervalSchedule() {
        let schedule = ScheduledWorkflow.Schedule.interval(300)
        if case .interval(let seconds) = schedule {
            XCTAssertEqual(seconds, 300)
        } else {
            XCTFail("Expected .interval schedule")
        }
    }

    func testDailySchedule() {
        let schedule = ScheduledWorkflow.Schedule.daily(hour: 6, minute: 30)
        if case .daily(let hour, let minute) = schedule {
            XCTAssertEqual(hour, 6)
            XCTAssertEqual(minute, 30)
        } else {
            XCTFail("Expected .daily schedule")
        }
    }

    func testPersistentSchedule() {
        let schedule = ScheduledWorkflow.Schedule.persistent
        if case .persistent = schedule {
            // Success
        } else {
            XCTFail("Expected .persistent schedule")
        }
    }

    func testWatchPathSchedule() {
        let schedule = ScheduledWorkflow.Schedule.watchPath("/some/path")
        if case .watchPath(let path) = schedule {
            XCTAssertEqual(path, "/some/path")
        } else {
            XCTFail("Expected .watchPath schedule")
        }
    }

    // MARK: - Model Creation

    func testWorkflowCreation() {
        let workflow = ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true,
            lastRunAt: nil
        )
        XCTAssertEqual(workflow.id, "process-llm")
        XCTAssertEqual(workflow.name, "Process LLM")
        XCTAssertEqual(workflow.scriptPath, "src/workflows/process-llm.ts")
        XCTAssertTrue(workflow.usesOllama)
        XCTAssertNil(workflow.lastRunAt)
    }

    func testWorkflowWithLastRunAt() {
        let date = Date()
        let workflow = ScheduledWorkflow(
            id: "daily-summary",
            name: "Daily Summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true,
            lastRunAt: date
        )
        XCTAssertEqual(workflow.lastRunAt, date)
    }

    // MARK: - isDue: Interval Schedules

    func testIsDueWhenNeverRun() {
        let workflow = ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true,
            lastRunAt: nil
        )
        XCTAssertTrue(workflow.isDue, "Workflow that never ran should be due")
    }

    func testIsDueWhenJustRan() {
        let workflow = ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true,
            lastRunAt: Date()
        )
        XCTAssertFalse(workflow.isDue, "Workflow that just ran should not be due")
    }

    func testIsDueWhenIntervalElapsed() {
        let fiveMinutesAgo = Date().addingTimeInterval(-301)
        let workflow = ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true,
            lastRunAt: fiveMinutesAgo
        )
        XCTAssertTrue(workflow.isDue, "Workflow should be due after interval elapsed")
    }

    func testIsNotDueWhenIntervalNotElapsed() {
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        let workflow = ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true,
            lastRunAt: twoMinutesAgo
        )
        XCTAssertFalse(workflow.isDue, "Workflow should not be due before interval elapsed")
    }

    func testIsDueAtExactInterval() {
        let exactlyFiveMinutesAgo = Date().addingTimeInterval(-300)
        let workflow = ScheduledWorkflow(
            id: "process-llm",
            name: "Process LLM",
            scriptPath: "src/workflows/process-llm.ts",
            schedule: .interval(300),
            usesOllama: true,
            lastRunAt: exactlyFiveMinutesAgo
        )
        XCTAssertTrue(workflow.isDue, "Workflow should be due at exactly the interval boundary")
    }

    // MARK: - isDue: Daily Schedules

    func testDailyIsDueWhenNeverRun() {
        let workflow = ScheduledWorkflow(
            id: "daily-summary",
            name: "Daily Summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true,
            lastRunAt: nil
        )
        XCTAssertTrue(workflow.isDue, "Daily workflow that never ran should be due")
    }

    func testDailyIsNotDueWhenRanToday() {
        // Create a date that is today but earlier
        let calendar = Calendar.current
        let now = Date()
        let todayEarlier = calendar.date(
            bySettingHour: max(calendar.component(.hour, from: now) - 1, 0),
            minute: 0,
            second: 0,
            of: now
        ) ?? now.addingTimeInterval(-3600)

        let workflow = ScheduledWorkflow(
            id: "daily-summary",
            name: "Daily Summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true,
            lastRunAt: todayEarlier
        )
        XCTAssertFalse(workflow.isDue, "Daily workflow that ran today should not be due")
    }

    func testDailyIsDueWhenRanYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let workflow = ScheduledWorkflow(
            id: "daily-summary",
            name: "Daily Summary",
            scriptPath: "src/workflows/daily-summary.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: true,
            lastRunAt: yesterday
        )
        XCTAssertTrue(workflow.isDue, "Daily workflow that ran yesterday should be due")
    }

    func testDailyIsDueWhenRanTwoDaysAgo() {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let workflow = ScheduledWorkflow(
            id: "export-obsidian",
            name: "Export Obsidian",
            scriptPath: "src/workflows/export-obsidian.ts",
            schedule: .daily(hour: 0, minute: 0),
            usesOllama: false,
            lastRunAt: twoDaysAgo
        )
        XCTAssertTrue(workflow.isDue, "Daily workflow that ran two days ago should be due")
    }

    // MARK: - isDue: Persistent and WatchPath

    func testPersistentIsNeverDue() {
        let workflow = ScheduledWorkflow(
            id: "server",
            name: "Selene Server",
            scriptPath: "src/server.ts",
            schedule: .persistent,
            usesOllama: false,
            lastRunAt: nil
        )
        XCTAssertFalse(workflow.isDue, "Persistent workflow should never be due (managed separately)")
    }

    func testPersistentIsNeverDueEvenWithNilLastRun() {
        let workflow = ScheduledWorkflow(
            id: "server",
            name: "Selene Server",
            scriptPath: "src/server.ts",
            schedule: .persistent,
            usesOllama: false,
            lastRunAt: nil
        )
        XCTAssertFalse(workflow.isDue)
    }

    func testWatchPathIsNeverDue() {
        let workflow = ScheduledWorkflow(
            id: "transcribe-voice-memos",
            name: "Transcribe Voice Memos",
            scriptPath: "src/workflows/transcribe-voice-memos.ts",
            schedule: .watchPath("/Users/chaseeasterling/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings"),
            usesOllama: false,
            lastRunAt: nil
        )
        XCTAssertFalse(workflow.isDue, "WatchPath workflow should never be due (managed separately)")
    }

    func testWatchPathIsNeverDueEvenWithOldLastRun() {
        let longAgo = Date.distantPast
        let workflow = ScheduledWorkflow(
            id: "transcribe-voice-memos",
            name: "Transcribe Voice Memos",
            scriptPath: "src/workflows/transcribe-voice-memos.ts",
            schedule: .watchPath("/some/path"),
            usesOllama: false,
            lastRunAt: longAgo
        )
        XCTAssertFalse(workflow.isDue)
    }

    // MARK: - allWorkflows

    func testAllWorkflowsCount() {
        XCTAssertEqual(ScheduledWorkflow.allWorkflows.count, 11, "Should define exactly 11 workflows")
    }

    func testAllWorkflowsHaveUniqueIds() {
        let ids = ScheduledWorkflow.allWorkflows.map(\.id)
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "All workflow IDs should be unique")
    }

    func testAllWorkflowsHaveUniqueNames() {
        let names = ScheduledWorkflow.allWorkflows.map(\.name)
        let uniqueNames = Set(names)
        XCTAssertEqual(names.count, uniqueNames.count, "All workflow names should be unique")
    }

    func testServerWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "server" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.name, "Selene Server")
        XCTAssertEqual(workflow?.scriptPath, "src/server.ts")
        XCTAssertFalse(workflow?.usesOllama ?? true)
        if case .persistent = workflow?.schedule {
            // Success
        } else {
            XCTFail("Server should have persistent schedule")
        }
    }

    func testProcessLLMWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "process-llm" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/process-llm.ts")
        XCTAssertTrue(workflow?.usesOllama ?? false)
        if case .interval(let seconds) = workflow?.schedule {
            XCTAssertEqual(seconds, 300)
        } else {
            XCTFail("process-llm should have interval schedule")
        }
    }

    func testExtractTasksWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "extract-tasks" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/extract-tasks.ts")
        XCTAssertTrue(workflow?.usesOllama ?? false)
        if case .interval(let seconds) = workflow?.schedule {
            XCTAssertEqual(seconds, 300)
        } else {
            XCTFail("extract-tasks should have interval schedule")
        }
    }

    func testComputeRelationshipsWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "compute-relationships" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/compute-relationships.ts")
        XCTAssertFalse(workflow?.usesOllama ?? true)
        if case .interval(let seconds) = workflow?.schedule {
            XCTAssertEqual(seconds, 600)
        } else {
            XCTFail("compute-relationships should have interval schedule")
        }
    }

    func testIndexVectorsWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "index-vectors" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/index-vectors.ts")
        XCTAssertTrue(workflow?.usesOllama ?? false)
        if case .interval(let seconds) = workflow?.schedule {
            XCTAssertEqual(seconds, 600)
        } else {
            XCTFail("index-vectors should have interval schedule")
        }
    }

    func testDetectThreadsWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "detect-threads" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/detect-threads.ts")
        XCTAssertTrue(workflow?.usesOllama ?? false)
        if case .interval(let seconds) = workflow?.schedule {
            XCTAssertEqual(seconds, 1800)
        } else {
            XCTFail("detect-threads should have interval schedule")
        }
    }

    func testReconsolidateThreadsWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "reconsolidate-threads" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/reconsolidate-threads.ts")
        XCTAssertTrue(workflow?.usesOllama ?? false)
        if case .interval(let seconds) = workflow?.schedule {
            XCTAssertEqual(seconds, 3600)
        } else {
            XCTFail("reconsolidate-threads should have interval schedule")
        }
    }

    func testExportObsidianWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "export-obsidian" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/export-obsidian.ts")
        XCTAssertFalse(workflow?.usesOllama ?? true)
        if case .daily(let hour, let minute) = workflow?.schedule {
            XCTAssertEqual(hour, 0)
            XCTAssertEqual(minute, 0)
        } else {
            XCTFail("export-obsidian should have daily schedule")
        }
    }

    func testDailySummaryWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "daily-summary" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/daily-summary.ts")
        XCTAssertTrue(workflow?.usesOllama ?? false)
        if case .daily(let hour, let minute) = workflow?.schedule {
            XCTAssertEqual(hour, 0)
            XCTAssertEqual(minute, 0)
        } else {
            XCTFail("daily-summary should have daily schedule")
        }
    }

    func testSendDigestWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "send-digest" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/send-digest.ts")
        XCTAssertFalse(workflow?.usesOllama ?? true)
        if case .daily(let hour, let minute) = workflow?.schedule {
            XCTAssertEqual(hour, 6)
            XCTAssertEqual(minute, 0)
        } else {
            XCTFail("send-digest should have daily schedule")
        }
    }

    func testTranscribeVoiceMemosWorkflow() {
        let workflow = ScheduledWorkflow.allWorkflows.first { $0.id == "transcribe-voice-memos" }
        XCTAssertNotNil(workflow)
        XCTAssertEqual(workflow?.scriptPath, "src/workflows/transcribe-voice-memos.ts")
        XCTAssertFalse(workflow?.usesOllama ?? true)
        if case .watchPath(let path) = workflow?.schedule {
            XCTAssertTrue(path.contains("VoiceMemos"), "Watch path should reference VoiceMemos directory")
        } else {
            XCTFail("transcribe-voice-memos should have watchPath schedule")
        }
    }

    // MARK: - Ollama Workflow Filtering

    func testOllamaWorkflowCount() {
        let ollamaWorkflows = ScheduledWorkflow.allWorkflows.filter(\.usesOllama)
        XCTAssertEqual(ollamaWorkflows.count, 6, "Should have exactly 6 Ollama-dependent workflows")
    }

    func testOllamaWorkflowIds() {
        let ollamaIds = Set(ScheduledWorkflow.allWorkflows.filter(\.usesOllama).map(\.id))
        let expected: Set<String> = [
            "process-llm",
            "extract-tasks",
            "index-vectors",
            "detect-threads",
            "reconsolidate-threads",
            "daily-summary"
        ]
        XCTAssertEqual(ollamaIds, expected)
    }

    func testNonOllamaWorkflowIds() {
        let nonOllamaIds = Set(ScheduledWorkflow.allWorkflows.filter { !$0.usesOllama }.map(\.id))
        let expected: Set<String> = [
            "server",
            "compute-relationships",
            "export-obsidian",
            "send-digest",
            "transcribe-voice-memos"
        ]
        XCTAssertEqual(nonOllamaIds, expected)
    }

    // MARK: - Identifiable

    func testIdentifiableConformance() {
        let workflow = ScheduledWorkflow(
            id: "test-workflow",
            name: "Test",
            scriptPath: "test.ts",
            schedule: .interval(60),
            usesOllama: false,
            lastRunAt: nil
        )
        // Identifiable conformance means .id returns the id property
        XCTAssertEqual(workflow.id, "test-workflow")
    }

    // MARK: - Schedule Equatable

    func testScheduleEquatableInterval() {
        XCTAssertEqual(
            ScheduledWorkflow.Schedule.interval(300),
            ScheduledWorkflow.Schedule.interval(300)
        )
        XCTAssertNotEqual(
            ScheduledWorkflow.Schedule.interval(300),
            ScheduledWorkflow.Schedule.interval(600)
        )
    }

    func testScheduleEquatableDaily() {
        XCTAssertEqual(
            ScheduledWorkflow.Schedule.daily(hour: 6, minute: 0),
            ScheduledWorkflow.Schedule.daily(hour: 6, minute: 0)
        )
        XCTAssertNotEqual(
            ScheduledWorkflow.Schedule.daily(hour: 6, minute: 0),
            ScheduledWorkflow.Schedule.daily(hour: 0, minute: 0)
        )
    }

    func testScheduleEquatablePersistent() {
        XCTAssertEqual(
            ScheduledWorkflow.Schedule.persistent,
            ScheduledWorkflow.Schedule.persistent
        )
    }

    func testScheduleEquatableWatchPath() {
        XCTAssertEqual(
            ScheduledWorkflow.Schedule.watchPath("/a"),
            ScheduledWorkflow.Schedule.watchPath("/a")
        )
        XCTAssertNotEqual(
            ScheduledWorkflow.Schedule.watchPath("/a"),
            ScheduledWorkflow.Schedule.watchPath("/b")
        )
    }

    func testScheduleEquatableDifferentCases() {
        XCTAssertNotEqual(
            ScheduledWorkflow.Schedule.interval(300),
            ScheduledWorkflow.Schedule.daily(hour: 0, minute: 5)
        )
        XCTAssertNotEqual(
            ScheduledWorkflow.Schedule.persistent,
            ScheduledWorkflow.Schedule.watchPath("/path")
        )
    }

    // MARK: - Mock (DEBUG only)

    func testMockDefaults() {
        let workflow = ScheduledWorkflow.mock()
        XCTAssertEqual(workflow.id, "test-workflow")
        XCTAssertEqual(workflow.name, "Test Workflow")
        XCTAssertEqual(workflow.scriptPath, "src/workflows/test.ts")
        XCTAssertFalse(workflow.usesOllama)
        XCTAssertNil(workflow.lastRunAt)
        if case .interval(let seconds) = workflow.schedule {
            XCTAssertEqual(seconds, 300)
        } else {
            XCTFail("Default mock should have interval schedule")
        }
    }

    func testMockCustomValues() {
        let date = Date()
        let workflow = ScheduledWorkflow.mock(
            id: "custom",
            name: "Custom Workflow",
            scriptPath: "custom.ts",
            schedule: .daily(hour: 8, minute: 30),
            usesOllama: true,
            lastRunAt: date
        )
        XCTAssertEqual(workflow.id, "custom")
        XCTAssertEqual(workflow.name, "Custom Workflow")
        XCTAssertEqual(workflow.scriptPath, "custom.ts")
        XCTAssertTrue(workflow.usesOllama)
        XCTAssertEqual(workflow.lastRunAt, date)
    }

    // MARK: - allWorkflows lastRunAt defaults

    func testAllWorkflowsStartWithNilLastRunAt() {
        for workflow in ScheduledWorkflow.allWorkflows {
            XCTAssertNil(workflow.lastRunAt, "\(workflow.id) should start with nil lastRunAt")
        }
    }

    // MARK: - projectRoot

    func testProjectRootIsAbsolutePath() {
        let root = ScheduledWorkflow.projectRoot
        XCTAssertTrue(root.hasPrefix("/"), "projectRoot should be an absolute path")
    }

    func testProjectRootContainsSelene() {
        let root = ScheduledWorkflow.projectRoot
        XCTAssertTrue(root.contains("selene"), "projectRoot should reference selene")
    }
}
