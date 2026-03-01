# SeleneChat Debug System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Give Claude Code visibility into SeleneChat's runtime state for autonomous debugging via continuous logging, on-demand snapshots, and error alerting.

**Architecture:** A `DebugLogger` singleton handles continuous logging to `/tmp/selenechat-debug.log` with 5MB rotation. A `DebugSnapshotService` watches for trigger files and dumps app state to JSON. Services and stores conform to `DebugSnapshotProvider` protocol to contribute their state to snapshots.

**Tech Stack:** Swift 5.9+, Foundation (FileHandle, DispatchSource), SwiftUI, `#if DEBUG` compilation flags

---

## Task 1: Create DebugLogger Singleton

**Files:**
- Create: `SeleneChat/Sources/Debug/DebugLogger.swift`
- Test: `SeleneChat/Tests/DebugLoggerTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/DebugLoggerTests.swift`:

```swift
import XCTest
@testable import SeleneChat

final class DebugLoggerTests: XCTestCase {

    var logger: DebugLogger!
    let testLogPath = "/tmp/selenechat-debug-test.log"

    override func setUp() {
        super.setUp()
        // Clean up any existing test log
        try? FileManager.default.removeItem(atPath: testLogPath)
        logger = DebugLogger(logPath: testLogPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: testLogPath)
        super.tearDown()
    }

    func test_log_writesToFile() {
        // Act
        logger.log(.state, "TestComponent.value: 0 → 1")

        // Assert
        let content = try? String(contentsOfFile: testLogPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("STATE") ?? false)
        XCTAssertTrue(content?.contains("TestComponent.value: 0 → 1") ?? false)
    }

    func test_log_includesTimestamp() {
        // Act
        logger.log(.error, "Test error message")

        // Assert
        let content = try? String(contentsOfFile: testLogPath, encoding: .utf8)
        XCTAssertNotNil(content)
        // Should contain date in format [YYYY-MM-DD HH:MM:SS]
        XCTAssertTrue(content?.contains("[202") ?? false)
    }

    func test_logCategory_formatsCorrectly() {
        // Act
        logger.log(.state, "state message")
        logger.log(.error, "error message")
        logger.log(.nav, "nav message")
        logger.log(.action, "action message")

        // Assert
        let content = try? String(contentsOfFile: testLogPath, encoding: .utf8)
        XCTAssertTrue(content?.contains("STATE") ?? false)
        XCTAssertTrue(content?.contains("ERROR") ?? false)
        XCTAssertTrue(content?.contains("NAV") ?? false)
        XCTAssertTrue(content?.contains("ACTION") ?? false)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugLoggerTests 2>&1 | tail -20
```

Expected: FAIL - "cannot find 'DebugLogger' in scope"

**Step 3: Write minimal implementation**

Create `SeleneChat/Sources/Debug/DebugLogger.swift`:

```swift
import Foundation

#if DEBUG

enum LogCategory: String {
    case state = "STATE"
    case error = "ERROR"
    case nav = "NAV"
    case action = "ACTION"
}

final class DebugLogger {
    static let shared = DebugLogger()

    private let logPath: String
    private let dateFormatter: DateFormatter
    private let fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.selenechat.debuglogger")

    init(logPath: String = "/tmp/selenechat-debug.log") {
        self.logPath = logPath

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Create file if doesn't exist
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        self.fileHandle = FileHandle(forWritingAtPath: logPath)
        self.fileHandle?.seekToEndOfFile()
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ category: LogCategory, _ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            let timestamp = self.dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] \(category.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) | \(message)\n"

            if let data = logLine.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }
}

#endif
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugLoggerTests 2>&1 | tail -20
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Debug/DebugLogger.swift SeleneChat/Tests/DebugLoggerTests.swift
git commit -m "feat(debug): add DebugLogger with basic logging"
```

---

## Task 2: Add Log Rotation to DebugLogger

**Files:**
- Modify: `SeleneChat/Sources/Debug/DebugLogger.swift`
- Modify: `SeleneChat/Tests/DebugLoggerTests.swift`

**Step 1: Write the failing test**

Add to `DebugLoggerTests.swift`:

```swift
    func test_rotation_rotatesWhenExceedsMaxSize() {
        // Arrange - use tiny max size for testing
        let smallLogger = DebugLogger(logPath: testLogPath, maxSizeBytes: 100)

        // Act - write enough to exceed 100 bytes
        for i in 0..<10 {
            smallLogger.log(.state, "This is a longer message to fill up the log file quickly \(i)")
        }

        // Allow queue to flush
        Thread.sleep(forTimeInterval: 0.1)

        // Assert - backup file should exist
        let backupPath = testLogPath + ".old"
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupPath))

        // Cleanup
        try? FileManager.default.removeItem(atPath: backupPath)
    }

    func test_rotation_deletesOldBackup() {
        // Arrange
        let backupPath = testLogPath + ".old"
        FileManager.default.createFile(atPath: backupPath, contents: "old backup".data(using: .utf8))
        let smallLogger = DebugLogger(logPath: testLogPath, maxSizeBytes: 50)

        // Act - trigger rotation
        for i in 0..<10 {
            smallLogger.log(.state, "Message \(i) to trigger rotation")
        }

        Thread.sleep(forTimeInterval: 0.1)

        // Assert - backup exists but is new content
        let backupContent = try? String(contentsOfFile: backupPath, encoding: .utf8)
        XCTAssertNotNil(backupContent)
        XCTAssertFalse(backupContent?.contains("old backup") ?? true)

        // Cleanup
        try? FileManager.default.removeItem(atPath: backupPath)
    }
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugLoggerTests 2>&1 | tail -20
```

Expected: FAIL - init doesn't accept maxSizeBytes parameter

**Step 3: Update implementation with rotation**

Update `DebugLogger.swift`:

```swift
import Foundation

#if DEBUG

enum LogCategory: String {
    case state = "STATE"
    case error = "ERROR"
    case nav = "NAV"
    case action = "ACTION"
}

final class DebugLogger {
    static let shared = DebugLogger()

    private let logPath: String
    private let maxSizeBytes: UInt64
    private let dateFormatter: DateFormatter
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.selenechat.debuglogger")

    init(logPath: String = "/tmp/selenechat-debug.log", maxSizeBytes: UInt64 = 5 * 1024 * 1024) {
        self.logPath = logPath
        self.maxSizeBytes = maxSizeBytes

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        openLogFile()
    }

    deinit {
        try? fileHandle?.close()
    }

    private func openLogFile() {
        // Create file if doesn't exist
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        self.fileHandle = FileHandle(forWritingAtPath: logPath)
        self.fileHandle?.seekToEndOfFile()
    }

    func log(_ category: LogCategory, _ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateIfNeeded()

            let timestamp = self.dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] \(category.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) | \(message)\n"

            if let data = logLine.data(using: .utf8) {
                self.fileHandle?.write(data)
            }
        }
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
              let fileSize = attributes[.size] as? UInt64,
              fileSize >= maxSizeBytes else {
            return
        }

        // Close current handle
        try? fileHandle?.close()

        // Delete old backup if exists
        let backupPath = logPath + ".old"
        try? FileManager.default.removeItem(atPath: backupPath)

        // Rename current log to backup
        try? FileManager.default.moveItem(atPath: logPath, toPath: backupPath)

        // Open fresh log file
        openLogFile()
    }
}

#endif
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugLoggerTests 2>&1 | tail -20
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Debug/DebugLogger.swift SeleneChat/Tests/DebugLoggerTests.swift
git commit -m "feat(debug): add log rotation at 5MB"
```

---

## Task 3: Create DebugSnapshotProvider Protocol

**Files:**
- Create: `SeleneChat/Sources/Debug/DebugSnapshotProvider.swift`
- Test: `SeleneChat/Tests/DebugSnapshotProviderTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/DebugSnapshotProviderTests.swift`:

```swift
import XCTest
@testable import SeleneChat

#if DEBUG

final class DebugSnapshotProviderTests: XCTestCase {

    func test_mockProvider_returnsSnapshot() {
        // Arrange
        let provider = MockSnapshotProvider()

        // Act
        let snapshot = provider.debugSnapshot()

        // Assert
        XCTAssertEqual(snapshot["testKey"] as? String, "testValue")
    }

    func test_snapshot_isSerializableToJSON() throws {
        // Arrange
        let provider = MockSnapshotProvider()
        let snapshot = provider.debugSnapshot()

        // Act
        let data = try JSONSerialization.data(withJSONObject: snapshot)

        // Assert
        XCTAssertGreaterThan(data.count, 0)
    }
}

// Mock implementation for testing
class MockSnapshotProvider: DebugSnapshotProvider {
    func debugSnapshot() -> [String: Any] {
        return ["testKey": "testValue", "count": 42]
    }
}

#endif
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugSnapshotProviderTests 2>&1 | tail -20
```

Expected: FAIL - "cannot find 'DebugSnapshotProvider' in scope"

**Step 3: Write implementation**

Create `SeleneChat/Sources/Debug/DebugSnapshotProvider.swift`:

```swift
import Foundation

#if DEBUG

/// Protocol for types that can contribute to debug snapshots
protocol DebugSnapshotProvider {
    /// Returns a dictionary representation of the current state
    /// Values must be JSON-serializable (String, Int, Double, Bool, Array, Dictionary)
    func debugSnapshot() -> [String: Any]
}

#endif
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugSnapshotProviderTests 2>&1 | tail -20
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Debug/DebugSnapshotProvider.swift SeleneChat/Tests/DebugSnapshotProviderTests.swift
git commit -m "feat(debug): add DebugSnapshotProvider protocol"
```

---

## Task 4: Create DebugSnapshotService

**Files:**
- Create: `SeleneChat/Sources/Debug/DebugSnapshotService.swift`
- Test: `SeleneChat/Tests/DebugSnapshotServiceTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/DebugSnapshotServiceTests.swift`:

```swift
import XCTest
@testable import SeleneChat

#if DEBUG

final class DebugSnapshotServiceTests: XCTestCase {

    let requestPath = "/tmp/selenechat-snapshot-request-test"
    let outputPath = "/tmp/selenechat-snapshot-test.json"

    override func setUp() {
        super.setUp()
        cleanup()
    }

    override func tearDown() {
        cleanup()
        super.tearDown()
    }

    private func cleanup() {
        try? FileManager.default.removeItem(atPath: requestPath)
        try? FileManager.default.removeItem(atPath: outputPath)
    }

    func test_generateSnapshot_writesJSONFile() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )
        let mockProvider = MockSnapshotProvider()
        service.registerProvider(named: "mock", provider: mockProvider)

        // Act
        service.generateSnapshot()

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))

        let content = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertNotNil(content)
        XCTAssertTrue(content?.contains("testKey") ?? false)
    }

    func test_generateSnapshot_includesTimestamp() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )

        // Act
        service.generateSnapshot()

        // Assert
        let content = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(content?.contains("timestamp") ?? false)
    }

    func test_checkForRequest_deletesRequestFile() {
        // Arrange
        let service = DebugSnapshotService(
            requestPath: requestPath,
            outputPath: outputPath
        )

        // Create request file
        FileManager.default.createFile(atPath: requestPath, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestPath))

        // Act
        service.checkForRequest()

        // Assert
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestPath))
    }
}

#endif
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugSnapshotServiceTests 2>&1 | tail -20
```

Expected: FAIL - "cannot find 'DebugSnapshotService' in scope"

**Step 3: Write implementation**

Create `SeleneChat/Sources/Debug/DebugSnapshotService.swift`:

```swift
import Foundation

#if DEBUG

final class DebugSnapshotService {
    static let shared = DebugSnapshotService()

    private let requestPath: String
    private let outputPath: String
    private var providers: [String: DebugSnapshotProvider] = [:]
    private var timer: Timer?
    private let dateFormatter: ISO8601DateFormatter

    init(
        requestPath: String = "/tmp/selenechat-snapshot-request",
        outputPath: String = "/tmp/selenechat-snapshot.json"
    ) {
        self.requestPath = requestPath
        self.outputPath = outputPath
        self.dateFormatter = ISO8601DateFormatter()
    }

    func registerProvider(named name: String, provider: DebugSnapshotProvider) {
        providers[name] = provider
    }

    func startWatching(interval: TimeInterval = 2.0) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForRequest()
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func checkForRequest() {
        guard FileManager.default.fileExists(atPath: requestPath) else {
            return
        }

        // Delete request file first
        try? FileManager.default.removeItem(atPath: requestPath)

        // Generate and write snapshot
        generateSnapshot()
    }

    func generateSnapshot() {
        var snapshot: [String: Any] = [
            "timestamp": dateFormatter.string(from: Date())
        ]

        // Collect from all providers
        for (name, provider) in providers {
            snapshot[name] = provider.debugSnapshot()
        }

        // Write to file
        do {
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            DebugLogger.shared.log(.error, "Failed to write snapshot: \(error.localizedDescription)")
        }
    }
}

#endif
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugSnapshotServiceTests 2>&1 | tail -20
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Debug/DebugSnapshotService.swift SeleneChat/Tests/DebugSnapshotServiceTests.swift
git commit -m "feat(debug): add DebugSnapshotService with file trigger"
```

---

## Task 5: Add Error Alerting

**Files:**
- Modify: `SeleneChat/Sources/Debug/DebugLogger.swift`
- Modify: `SeleneChat/Tests/DebugLoggerTests.swift`

**Step 1: Write the failing test**

Add to `DebugLoggerTests.swift`:

```swift
    func test_logError_writesToErrorFile() {
        // Arrange
        let errorPath = "/tmp/selenechat-last-error-test"
        try? FileManager.default.removeItem(atPath: errorPath)
        let logger = DebugLogger(logPath: testLogPath, errorPath: errorPath)

        // Act
        logger.log(.error, "OllamaService.generate|connection refused")

        // Allow queue to flush
        Thread.sleep(forTimeInterval: 0.1)

        // Assert
        let errorContent = try? String(contentsOfFile: errorPath, encoding: .utf8)
        XCTAssertNotNil(errorContent)
        XCTAssertTrue(errorContent?.contains("OllamaService.generate") ?? false)
        XCTAssertTrue(errorContent?.contains("connection refused") ?? false)

        // Cleanup
        try? FileManager.default.removeItem(atPath: errorPath)
    }

    func test_logError_includesISOTimestamp() {
        // Arrange
        let errorPath = "/tmp/selenechat-last-error-test"
        try? FileManager.default.removeItem(atPath: errorPath)
        let logger = DebugLogger(logPath: testLogPath, errorPath: errorPath)

        // Act
        logger.log(.error, "TestError|test message")
        Thread.sleep(forTimeInterval: 0.1)

        // Assert
        let errorContent = try? String(contentsOfFile: errorPath, encoding: .utf8)
        XCTAssertNotNil(errorContent)
        // ISO format starts with year
        XCTAssertTrue(errorContent?.hasPrefix("202") ?? false)

        // Cleanup
        try? FileManager.default.removeItem(atPath: errorPath)
    }
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugLoggerTests 2>&1 | tail -20
```

Expected: FAIL - init doesn't accept errorPath parameter

**Step 3: Update implementation**

Update `DebugLogger.swift` init and log methods:

```swift
import Foundation

#if DEBUG

enum LogCategory: String {
    case state = "STATE"
    case error = "ERROR"
    case nav = "NAV"
    case action = "ACTION"
}

final class DebugLogger {
    static let shared = DebugLogger()

    private let logPath: String
    private let errorPath: String
    private let maxSizeBytes: UInt64
    private let dateFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.selenechat.debuglogger")

    init(
        logPath: String = "/tmp/selenechat-debug.log",
        errorPath: String = "/tmp/selenechat-last-error",
        maxSizeBytes: UInt64 = 5 * 1024 * 1024
    ) {
        self.logPath = logPath
        self.errorPath = errorPath
        self.maxSizeBytes = maxSizeBytes

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        self.isoFormatter = ISO8601DateFormatter()

        openLogFile()
    }

    deinit {
        try? fileHandle?.close()
    }

    private func openLogFile() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        self.fileHandle = FileHandle(forWritingAtPath: logPath)
        self.fileHandle?.seekToEndOfFile()
    }

    func log(_ category: LogCategory, _ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateIfNeeded()

            let timestamp = self.dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] \(category.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) | \(message)\n"

            if let data = logLine.data(using: .utf8) {
                self.fileHandle?.write(data)
            }

            // Write to error file for ERROR category
            if category == .error {
                self.writeErrorAlert(message)
            }
        }
    }

    private func writeErrorAlert(_ message: String) {
        let isoTimestamp = isoFormatter.string(from: Date())
        let errorLine = "\(isoTimestamp)|\(message)"

        try? errorLine.write(toFile: errorPath, atomically: true, encoding: .utf8)
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
              let fileSize = attributes[.size] as? UInt64,
              fileSize >= maxSizeBytes else {
            return
        }

        try? fileHandle?.close()

        let backupPath = logPath + ".old"
        try? FileManager.default.removeItem(atPath: backupPath)
        try? FileManager.default.moveItem(atPath: logPath, toPath: backupPath)

        openLogFile()
    }
}

#endif
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter DebugLoggerTests 2>&1 | tail -20
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Debug/DebugLogger.swift SeleneChat/Tests/DebugLoggerTests.swift
git commit -m "feat(debug): add error alerting to /tmp/selenechat-last-error"
```

---

## Task 6: Add Recent Actions Tracker

**Files:**
- Create: `SeleneChat/Sources/Debug/ActionTracker.swift`
- Test: `SeleneChat/Tests/ActionTrackerTests.swift`

**Step 1: Write the failing test**

Create `SeleneChat/Tests/ActionTrackerTests.swift`:

```swift
import XCTest
@testable import SeleneChat

#if DEBUG

final class ActionTrackerTests: XCTestCase {

    func test_track_storesAction() {
        // Arrange
        let tracker = ActionTracker()

        // Act
        tracker.track(action: "tappedThread", params: ["id": "abc-123"])

        // Assert
        let actions = tracker.recentActions
        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?["action"] as? String, "tappedThread")
    }

    func test_track_limitsToMaxCount() {
        // Arrange
        let tracker = ActionTracker(maxActions: 3)

        // Act
        tracker.track(action: "action1", params: nil)
        tracker.track(action: "action2", params: nil)
        tracker.track(action: "action3", params: nil)
        tracker.track(action: "action4", params: nil)

        // Assert
        let actions = tracker.recentActions
        XCTAssertEqual(actions.count, 3)
        XCTAssertEqual(actions.last?["action"] as? String, "action4")
    }

    func test_track_includesTimestamp() {
        // Arrange
        let tracker = ActionTracker()

        // Act
        tracker.track(action: "test", params: nil)

        // Assert
        let action = tracker.recentActions.first
        XCTAssertNotNil(action?["time"])
    }

    func test_conformsToDebugSnapshotProvider() {
        // Arrange
        let tracker = ActionTracker()
        tracker.track(action: "test", params: ["key": "value"])

        // Act
        let snapshot = tracker.debugSnapshot()

        // Assert
        XCTAssertNotNil(snapshot["recentActions"])
    }
}

#endif
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter ActionTrackerTests 2>&1 | tail -20
```

Expected: FAIL - "cannot find 'ActionTracker' in scope"

**Step 3: Write implementation**

Create `SeleneChat/Sources/Debug/ActionTracker.swift`:

```swift
import Foundation

#if DEBUG

final class ActionTracker: DebugSnapshotProvider {
    static let shared = ActionTracker()

    private let maxActions: Int
    private var actions: [[String: Any]] = []
    private let queue = DispatchQueue(label: "com.selenechat.actiontracker")
    private let isoFormatter: ISO8601DateFormatter

    var recentActions: [[String: Any]] {
        queue.sync { actions }
    }

    init(maxActions: Int = 20) {
        self.maxActions = maxActions
        self.isoFormatter = ISO8601DateFormatter()
    }

    func track(action: String, params: [String: Any]?) {
        queue.async { [weak self] in
            guard let self = self else { return }

            var entry: [String: Any] = [
                "time": self.isoFormatter.string(from: Date()),
                "action": action
            ]

            if let params = params {
                entry["params"] = params
            }

            self.actions.append(entry)

            // Trim to max size
            if self.actions.count > self.maxActions {
                self.actions.removeFirst()
            }
        }
    }

    func debugSnapshot() -> [String: Any] {
        return ["recentActions": recentActions]
    }
}

#endif
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter ActionTrackerTests 2>&1 | tail -20
```

Expected: PASS

**Step 5: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Debug/ActionTracker.swift SeleneChat/Tests/ActionTrackerTests.swift
git commit -m "feat(debug): add ActionTracker for recent user actions"
```

---

## Task 7: Create Debug Journal Skill

**Files:**
- Create: `.claude/skills/log-debug-fix.md`
- Create: `docs/debug-journal.md`

**Step 1: Create the skill file**

Create `.claude/skills/log-debug-fix.md`:

```markdown
---
name: log-debug-fix
description: Log a solved debug issue to the debug journal
---

# Log Debug Fix

When invoked after solving a debug issue, document the solution.

## Process

1. Summarize the issue that was just debugged
2. Format using the template below
3. Append to `docs/debug-journal.md`
4. Commit the update

## Template

```markdown
## YYYY-MM-DD: [Brief issue title]

**Symptoms:** [What was observed - error message, visual issue, wrong behavior]
**Context:** [What was happening when it occurred - which view, what action]
**Cause:** [Root cause identified]
**Solution:** [What fixed it]
**Files:** [Affected files with line numbers]
**Prevention:** [Optional - how to avoid similar issues]

---
```

## Example Usage

After fixing a bug where the planning view showed an empty list despite having data:

```markdown
## 2026-01-01: Planning view shows empty list

**Symptoms:** PlanningView renders but shows no threads despite database having 3 threads
**Context:** Opening Planning tab after app launch, database confirmed to have data
**Cause:** Query was using wrong column name - `user_id` instead of `thread_owner`
**Solution:** Changed WHERE clause in `PlanningService.fetchThreads()` from `WHERE user_id = ?` to `WHERE thread_owner = ?`
**Files:** SeleneChat/Sources/Services/PlanningService.swift:45
**Prevention:** Add integration test that verifies threads appear after creation

---
```
```

**Step 2: Create the journal file**

Create `docs/debug-journal.md`:

```markdown
# SeleneChat Debug Journal

Solved issues and their solutions for future reference.

---

<!-- New entries go above this line -->
```

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add .claude/skills/log-debug-fix.md docs/debug-journal.md
git commit -m "feat(debug): add /log-debug-fix skill and debug journal"
```

---

## Task 8: Integrate Debug System with App

**Files:**
- Modify: `SeleneChat/Sources/App/SeleneChatApp.swift`

**Step 1: Add debug initialization**

Read current file and modify to add debug system startup:

```swift
import SwiftUI
import AppKit

@main
struct SeleneChatApp: App {
    @StateObject private var databaseService = DatabaseService.shared
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var compressionService = CompressionService(databaseService: DatabaseService.shared)

    init() {
        // Activate the app so it appears in the foreground
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        #if DEBUG
        // Initialize debug system
        setupDebugSystem()
        #endif
    }

    #if DEBUG
    private func setupDebugSystem() {
        DebugLogger.shared.log(.state, "App launched")

        // Register snapshot providers
        DebugSnapshotService.shared.registerProvider(named: "actions", provider: ActionTracker.shared)

        // Start watching for snapshot requests
        DebugSnapshotService.shared.startWatching()
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(databaseService)
                .environmentObject(chatViewModel)
                .frame(minWidth: 800, minHeight: 600)
                .task {
                    // Run compression check asynchronously on launch
                    await compressionService.checkAndCompressSessions()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environmentObject(databaseService)
        }
    }
}
```

**Step 2: Verify build passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift build 2>&1 | tail -10
```

Expected: Build complete

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/App/SeleneChatApp.swift
git commit -m "feat(debug): integrate debug system with app startup"
```

---

## Task 9: Add Logging to OllamaService

**Files:**
- Modify: `SeleneChat/Sources/Services/OllamaService.swift`

**Step 1: Add logging calls to OllamaService**

Add `#if DEBUG` blocks at key points:

```swift
// Add after successful generate response (around line 125):
#if DEBUG
DebugLogger.shared.log(.state, "OllamaService.generate: success, response length=\(generateResponse.response.count)")
#endif

// Add in catch block for OllamaError (around line 128):
#if DEBUG
DebugLogger.shared.log(.error, "OllamaService.generate|\(error.localizedDescription)")
#endif

// Add in final catch block (around line 131):
#if DEBUG
DebugLogger.shared.log(.error, "OllamaService.generate|network error: \(error.localizedDescription)")
#endif

// Add in isAvailable when returning false (around line 68):
#if DEBUG
DebugLogger.shared.log(.state, "OllamaService.isAvailable: false (status \(httpResponse.statusCode))")
#endif
```

**Step 2: Verify build passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift build 2>&1 | tail -10
```

Expected: Build complete

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Services/OllamaService.swift
git commit -m "feat(debug): add debug logging to OllamaService"
```

---

## Task 10: Add Logging to DatabaseService

**Files:**
- Modify: `SeleneChat/Sources/Services/DatabaseService.swift`

**Step 1: Identify key state changes in DatabaseService**

Add logging at:
- Connection success/failure
- Query errors
- Key operations (save, delete, update)

Example patterns:

```swift
// After successful connection:
#if DEBUG
DebugLogger.shared.log(.state, "DatabaseService.connected: \(dbPath)")
#endif

// After query errors:
#if DEBUG
DebugLogger.shared.log(.error, "DatabaseService.query|\(error.localizedDescription)")
#endif

// After state changes:
#if DEBUG
DebugLogger.shared.log(.state, "DatabaseService.sessions.count: \(oldCount) → \(newCount)")
#endif
```

**Step 2: Verify build passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift build 2>&1 | tail -10
```

Expected: Build complete

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Services/DatabaseService.swift
git commit -m "feat(debug): add debug logging to DatabaseService"
```

---

## Task 11: Add Navigation Logging to Views

**Files:**
- Modify: `SeleneChat/Sources/App/ContentView.swift`
- Modify: `SeleneChat/Sources/Views/ChatView.swift`
- Modify: `SeleneChat/Sources/Views/PlanningView.swift`

**Step 1: Add onAppear logging to main views**

Pattern for each view:

```swift
.onAppear {
    #if DEBUG
    DebugLogger.shared.log(.nav, "Appeared: ViewName")
    ActionTracker.shared.track(action: "viewAppeared", params: ["view": "ViewName"])
    #endif
}
.onDisappear {
    #if DEBUG
    DebugLogger.shared.log(.nav, "Disappeared: ViewName")
    #endif
}
```

**Step 2: Verify build passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift build 2>&1 | tail -10
```

Expected: Build complete

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/App/ContentView.swift SeleneChat/Sources/Views/ChatView.swift SeleneChat/Sources/Views/PlanningView.swift
git commit -m "feat(debug): add navigation logging to main views"
```

---

## Task 12: Make ChatViewModel a DebugSnapshotProvider

**Files:**
- Modify: `SeleneChat/Sources/Services/ChatViewModel.swift`

**Step 1: Add DebugSnapshotProvider conformance**

```swift
#if DEBUG
extension ChatViewModel: DebugSnapshotProvider {
    func debugSnapshot() -> [String: Any] {
        return [
            "messagesCount": messages.count,
            "isLoading": isLoading,
            "currentSessionId": currentSession?.id.uuidString ?? "none",
            "error": errorMessage ?? "none"
        ]
    }
}
#endif
```

**Step 2: Register in SeleneChatApp.swift**

Add to `setupDebugSystem()`:

```swift
DebugSnapshotService.shared.registerProvider(named: "chatViewModel", provider: chatViewModel)
```

**Step 3: Verify build passes**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift build 2>&1 | tail -10
```

Expected: Build complete

**Step 4: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Sources/Services/ChatViewModel.swift SeleneChat/Sources/App/SeleneChatApp.swift
git commit -m "feat(debug): make ChatViewModel a DebugSnapshotProvider"
```

---

## Task 13: Final Integration Test

**Files:**
- Create: `SeleneChat/Tests/DebugSystemIntegrationTests.swift`

**Step 1: Write integration test**

```swift
import XCTest
@testable import SeleneChat

#if DEBUG

final class DebugSystemIntegrationTests: XCTestCase {

    let logPath = "/tmp/selenechat-debug-integration-test.log"
    let requestPath = "/tmp/selenechat-snapshot-request-integration-test"
    let outputPath = "/tmp/selenechat-snapshot-integration-test.json"

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: logPath)
        try? FileManager.default.removeItem(atPath: requestPath)
        try? FileManager.default.removeItem(atPath: outputPath)
        super.tearDown()
    }

    func test_fullDebugWorkflow() {
        // Arrange
        let logger = DebugLogger(logPath: logPath)
        let snapshotService = DebugSnapshotService(requestPath: requestPath, outputPath: outputPath)
        let actionTracker = ActionTracker()

        snapshotService.registerProvider(named: "actions", provider: actionTracker)

        // Act - simulate app activity
        logger.log(.state, "Test started")
        actionTracker.track(action: "testAction", params: ["key": "value"])
        logger.log(.nav, "Navigated to TestView")

        // Trigger snapshot
        FileManager.default.createFile(atPath: requestPath, contents: nil)
        snapshotService.checkForRequest()

        // Assert - verify all files created
        XCTAssertTrue(FileManager.default.fileExists(atPath: logPath), "Log file should exist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath), "Snapshot file should exist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestPath), "Request file should be deleted")

        // Verify log content
        let logContent = try? String(contentsOfFile: logPath, encoding: .utf8)
        XCTAssertTrue(logContent?.contains("Test started") ?? false)
        XCTAssertTrue(logContent?.contains("NAV") ?? false)

        // Verify snapshot content
        let snapshotContent = try? String(contentsOfFile: outputPath, encoding: .utf8)
        XCTAssertTrue(snapshotContent?.contains("testAction") ?? false)
        XCTAssertTrue(snapshotContent?.contains("timestamp") ?? false)
    }
}

#endif
```

**Step 2: Run all debug tests**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system/SeleneChat && swift test --filter Debug 2>&1 | tail -30
```

Expected: All tests pass

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/Tests/DebugSystemIntegrationTests.swift
git commit -m "test(debug): add integration test for full debug workflow"
```

---

## Task 14: Update Documentation

**Files:**
- Update: `SeleneChat/README.md`
- Update: `SeleneChat/CLAUDE.md`

**Step 1: Add Debug System section to README.md**

Add before "## Privacy Model":

```markdown
## Debug System (Development)

In DEBUG builds, SeleneChat includes a debug system for Claude Code visibility:

### Files
- `/tmp/selenechat-debug.log` - Continuous log of errors and state changes
- `/tmp/selenechat-snapshot.json` - Full app state dump (on request)
- `/tmp/selenechat-last-error` - Timestamp of most recent error

### Triggering a Snapshot
```bash
touch /tmp/selenechat-snapshot-request
sleep 2
cat /tmp/selenechat-snapshot.json
```

### Checking for Errors
```bash
cat /tmp/selenechat-last-error
tail -100 /tmp/selenechat-debug.log
```

See `docs/plans/2026-01-01-selenechat-debug-system-design.md` for full documentation.
```

**Step 2: Add to CLAUDE.md**

Add to Key Files section:

```markdown
- Sources/Debug/ - Debug logging and snapshot system (DEBUG builds only)
```

**Step 3: Commit**

```bash
cd /Users/chaseeasterling/selene/.worktrees/debug-system
git add SeleneChat/README.md SeleneChat/CLAUDE.md
git commit -m "docs: add debug system documentation"
```

---

## Summary

After completing all 14 tasks, the debug system provides:

1. **DebugLogger** - Continuous logging with 5MB rotation and error alerting
2. **DebugSnapshotProvider** - Protocol for state contribution
3. **DebugSnapshotService** - File-triggered state snapshots
4. **ActionTracker** - Recent user action tracking
5. **Integration** - Logging in OllamaService, DatabaseService, and main views
6. **Documentation** - Debug journal skill and updated docs

All code is wrapped in `#if DEBUG` to compile out in release builds.
