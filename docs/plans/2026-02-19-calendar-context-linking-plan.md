# Calendar Context Linking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically link notes to Apple Calendar events based on timing, so notes capture what you were doing when you wrote them.

**Architecture:** Swift CLI tool (`selene-calendar`) queries EventKit at ingestion time. Best-matching event stored as JSON metadata on the note. Displayed as subtle tag in SeleneChat/SeleneMobile. Fed to AI context builder.

**Tech Stack:** Swift/EventKit (CLI tool), TypeScript/better-sqlite3 (ingestion + migration), SwiftUI (display), SQLite.swift (SeleneChat DB reads)

---

### Task 1: Database Migration — Add `calendar_event` Column

**Files:**
- Create: `database/migrations/019_calendar_events.sql`

**Step 1: Write the migration**

```sql
-- 019_calendar_events.sql
-- Add calendar event context to notes
-- Stores best-matching calendar event as JSON when note is written during/after an event

ALTER TABLE raw_notes ADD COLUMN calendar_event TEXT;
```

**Step 2: Run the migration against the production database**

```bash
sqlite3 ~/selene-data/selene.db < database/migrations/019_calendar_events.sql
```

Expected: No output (success).

**Step 3: Verify**

```bash
sqlite3 ~/selene-data/selene.db ".schema raw_notes" | grep calendar_event
```

Expected: `calendar_event TEXT` appears in the schema.

**Step 4: Run against test database too**

```bash
sqlite3 ~/selene/data-test/selene-test.db < database/migrations/019_calendar_events.sql
```

**Step 5: Commit**

```bash
git add database/migrations/019_calendar_events.sql
git commit -m "feat: add calendar_event column to raw_notes"
```

---

### Task 2: TypeScript Types — Add CalendarEvent Interface

**Files:**
- Modify: `src/types/index.ts`
- Modify: `src/lib/db.ts`

**Step 1: Add CalendarEvent type to `src/types/index.ts`**

After the `ExportableNote` interface (line 48), add:

```typescript
// Calendar event context (from selene-calendar CLI)
export interface CalendarEvent {
  title: string;
  startDate: string;  // ISO 8601
  endDate: string;
  calendar: string;
  isAllDay: boolean;
}

export interface CalendarLookupResult {
  events: CalendarEvent[];
  matchType: 'during' | 'just_ended' | 'none';
}
```

**Step 2: Add `calendar_event` to `RawNote` interface in `src/lib/db.ts`**

Add to the `RawNote` interface (after line 65, after `test_run`):

```typescript
  calendar_event: string | null;
```

**Step 3: Add `updateCalendarEvent` helper to `src/lib/db.ts`**

After `insertNote` function (after line 128), add:

```typescript
// Helper: Update calendar event metadata on a note
export function updateCalendarEvent(noteId: number, calendarEvent: CalendarEvent): void {
  db.prepare('UPDATE raw_notes SET calendar_event = ? WHERE id = ?')
    .run(JSON.stringify(calendarEvent), noteId);
}
```

This requires importing `CalendarEvent` at the top of db.ts:

```typescript
import type { CalendarEvent } from '../types';
```

**Step 4: Verify TypeScript compiles**

```bash
npx tsc --noEmit
```

Expected: No errors.

**Step 5: Commit**

```bash
git add src/types/index.ts src/lib/db.ts
git commit -m "feat: add CalendarEvent types and DB helper"
```

---

### Task 3: Swift CLI Tool — `selene-calendar` Target

**Files:**
- Create: `SeleneChat/Sources/SeleneCalendar/main.swift`
- Modify: `SeleneChat/Package.swift`

**Step 1: Create the source directory**

```bash
mkdir -p SeleneChat/Sources/SeleneCalendar
```

**Step 2: Add the executable target to `Package.swift`**

After the SeleneMobile target (line 54), before the test target, add:

```swift
        .executableTarget(
            name: "selene-calendar",
            path: "Sources/SeleneCalendar"
        ),
```

Also add it to the products section (after line 22):

```swift
        .executable(
            name: "selene-calendar",
            targets: ["selene-calendar"]
        ),
```

**Step 3: Write `main.swift`**

Create `SeleneChat/Sources/SeleneCalendar/main.swift`:

```swift
import Foundation
import EventKit

// MARK: - Output Types

struct CalendarEventOutput: Codable {
    let title: String
    let startDate: String
    let endDate: String
    let calendar: String
    let isAllDay: Bool
}

struct CalendarLookupResult: Codable {
    let events: [CalendarEventOutput]
    let matchType: String  // "during", "just_ended", "none"
}

// MARK: - Argument Parsing

func parseArguments() -> Date? {
    let args = CommandLine.arguments
    guard let atIndex = args.firstIndex(of: "--at"),
          atIndex + 1 < args.count else {
        fputs("Usage: selene-calendar --at <ISO8601-timestamp>\n", stderr)
        fputs("Example: selene-calendar --at \"2026-02-19T17:30:00\"\n", stderr)
        return nil
    }

    let dateString = args[atIndex + 1]

    // Try ISO 8601 with timezone
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: dateString) {
        return date
    }

    // Try without fractional seconds
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: dateString) {
        return date
    }

    // Try local datetime (no timezone)
    let localFormatter = DateFormatter()
    localFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    localFormatter.timeZone = .current
    if let date = localFormatter.date(from: dateString) {
        return date
    }

    fputs("Error: Could not parse date '\(dateString)'\n", stderr)
    return nil
}

// MARK: - Calendar Query

func queryCalendar(at timestamp: Date) -> CalendarLookupResult {
    let store = EKEventStore()

    // Request access synchronously using semaphore
    let semaphore = DispatchSemaphore(value: 0)
    var accessGranted = false

    if #available(macOS 14.0, *) {
        store.requestFullAccessToEvents { granted, error in
            accessGranted = granted
            if let error = error {
                fputs("EventKit error: \(error.localizedDescription)\n", stderr)
            }
            semaphore.signal()
        }
    } else {
        store.requestAccess(to: .event) { granted, error in
            accessGranted = granted
            if let error = error {
                fputs("EventKit error: \(error.localizedDescription)\n", stderr)
            }
            semaphore.signal()
        }
    }

    semaphore.wait()

    guard accessGranted else {
        fputs("Calendar access not granted\n", stderr)
        return CalendarLookupResult(events: [], matchType: "none")
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]

    // Window: from 30 minutes before to the timestamp itself
    // This captures events happening "during" (start <= timestamp <= end)
    // AND events that "just ended" (ended within 30 min before timestamp)
    let windowStart = timestamp.addingTimeInterval(-30 * 60)  // 30 min before
    let windowEnd = timestamp.addingTimeInterval(1)            // just past the timestamp

    let predicate = store.predicateForEvents(
        withStart: windowStart,
        end: windowEnd,
        calendars: nil
    )
    let events = store.events(matching: predicate)

    var matchingEvents: [CalendarEventOutput] = []
    var matchType = "none"

    for event in events {
        // Skip all-day events
        if event.isAllDay { continue }

        let output = CalendarEventOutput(
            title: event.title ?? "Untitled",
            startDate: isoFormatter.string(from: event.startDate),
            endDate: isoFormatter.string(from: event.endDate),
            calendar: event.calendar.title,
            isAllDay: event.isAllDay
        )

        // Determine match type
        if event.startDate <= timestamp && event.endDate >= timestamp {
            matchType = "during"
        } else if event.endDate <= timestamp && event.endDate >= windowStart {
            if matchType != "during" {
                matchType = "just_ended"
            }
        }

        matchingEvents.append(output)
    }

    return CalendarLookupResult(events: matchingEvents, matchType: matchType)
}

// MARK: - Main

guard let timestamp = parseArguments() else {
    exit(1)
}

let result = queryCalendar(at: timestamp)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(result)
print(String(data: data, encoding: .utf8)!)
```

**Step 4: Build the CLI**

```bash
cd SeleneChat && swift build --product selene-calendar
```

Expected: Build succeeds. First run may prompt for Calendar access.

**Step 5: Test the CLI manually**

```bash
cd SeleneChat && .build/debug/selene-calendar --at "$(date -u +%Y-%m-%dT%H:%M:%S)"
```

Expected: JSON output with `events` array (may be empty if no current event). Verify:
- No crash
- Valid JSON output
- All-day events excluded

**Step 6: Commit**

```bash
git add SeleneChat/Sources/SeleneCalendar/main.swift SeleneChat/Package.swift
git commit -m "feat: add selene-calendar CLI tool with EventKit"
```

---

### Task 4: Swift CLI Tests

**Files:**
- Create: `SeleneChat/Tests/SeleneChatTests/Services/CalendarCLITests.swift`

**Step 1: Write tests for the CLI output parsing**

We can't mock EventKit easily in CLI tests, but we can test the JSON output format by running the binary and validating the structure.

```swift
import XCTest

final class CalendarCLITests: XCTestCase {

    private func runCalendarCLI(args: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        // Find the built binary
        let buildDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // SeleneChatTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // SeleneChat/
            .appendingPathComponent(".build/debug/selene-calendar")

        process.executableURL = buildDir
        process.arguments = args
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return (
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    func testNoArgumentsExitsWithError() throws {
        let result = try runCalendarCLI(args: [])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Usage:"))
    }

    func testInvalidDateExitsWithError() throws {
        let result = try runCalendarCLI(args: ["--at", "not-a-date"])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(result.stderr.contains("Could not parse"))
    }

    func testValidDateReturnsJSON() throws {
        let result = try runCalendarCLI(args: ["--at", "2026-02-19T17:30:00"])

        // Should exit successfully
        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")

        // Should output valid JSON
        let data = result.stdout.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        // Should have expected structure
        XCTAssertNotNil(json["events"])
        XCTAssertNotNil(json["matchType"])

        let events = json["events"] as! [[String: Any]]
        let matchType = json["matchType"] as! String

        // matchType should be one of the valid values
        XCTAssertTrue(["during", "just_ended", "none"].contains(matchType))

        // If events exist, verify structure
        for event in events {
            XCTAssertNotNil(event["title"])
            XCTAssertNotNil(event["startDate"])
            XCTAssertNotNil(event["endDate"])
            XCTAssertNotNil(event["calendar"])
            XCTAssertNotNil(event["isAllDay"])
            // All-day events should be excluded
            XCTAssertFalse(event["isAllDay"] as! Bool)
        }
    }

    func testISO8601WithTimezoneWorks() throws {
        let result = try runCalendarCLI(args: ["--at", "2026-02-19T17:30:00-06:00"])
        XCTAssertEqual(result.exitCode, 0, "stderr: \(result.stderr)")
    }
}
```

**Step 2: Build the CLI first (tests need the binary)**

```bash
cd SeleneChat && swift build --product selene-calendar
```

**Step 3: Run the tests**

```bash
cd SeleneChat && swift test --filter CalendarCLITests
```

Expected: All tests pass (the valid date test may return empty events array, which is fine).

**Step 4: Commit**

```bash
git add SeleneChat/Tests/SeleneChatTests/Services/CalendarCLITests.swift
git commit -m "test: add selene-calendar CLI tests"
```

---

### Task 5: Ingestion Integration — Call CLI After Saving Note

**Files:**
- Create: `src/lib/calendar.ts`
- Modify: `src/workflows/ingest.ts`
- Modify: `src/lib/index.ts` (if barrel exports exist)

**Step 1: Create the calendar lookup module `src/lib/calendar.ts`**

```typescript
import { execFile } from 'child_process';
import { promisify } from 'util';
import { resolve } from 'path';
import { logger } from './logger';
import type { CalendarEvent, CalendarLookupResult } from '../types';

const execFileAsync = promisify(execFile);

const CALENDAR_CLI_PATH = resolve(__dirname, '../../SeleneChat/.build/release/selene-calendar');

/**
 * Query Apple Calendar for events around a timestamp.
 * Best-effort: returns null on any failure (missing binary, no permission, etc.)
 */
export async function queryCalendar(timestamp: string): Promise<CalendarLookupResult | null> {
  try {
    const { stdout, stderr } = await execFileAsync(CALENDAR_CLI_PATH, ['--at', timestamp], {
      timeout: 5000,  // 5 second timeout
    });

    if (stderr) {
      logger.warn({ stderr }, 'selene-calendar stderr output');
    }

    const result: CalendarLookupResult = JSON.parse(stdout);
    return result;
  } catch (err) {
    logger.warn({ err, timestamp }, 'Calendar lookup failed (best-effort, continuing)');
    return null;
  }
}

/**
 * Pick the best matching event from a list.
 * Prefers: shorter events (more specific) over longer ones.
 */
export function pickBestEvent(events: CalendarEvent[]): CalendarEvent | null {
  if (events.length === 0) return null;

  // Filter out all-day events (shouldn't be here, but safety check)
  const timed = events.filter(e => !e.isAllDay);
  if (timed.length === 0) return null;

  // Sort by duration ascending (shortest = most specific)
  return timed.sort((a, b) => {
    const durationA = new Date(a.endDate).getTime() - new Date(a.startDate).getTime();
    const durationB = new Date(b.endDate).getTime() - new Date(b.startDate).getTime();
    return durationA - durationB;
  })[0];
}
```

**Step 2: Update `src/workflows/ingest.ts` to call calendar lookup after insert**

Replace the existing function body to add calendar enrichment after line 36 (after insertNote):

```typescript
import { createHash } from 'crypto';
import { createWorkflowLogger, findByContentHash, insertNote, updateCalendarEvent } from '../lib';
import { queryCalendar, pickBestEvent } from '../lib/calendar';
import type { IngestInput, IngestResult } from '../types';

const log = createWorkflowLogger('ingest');

export async function ingest(input: IngestInput): Promise<IngestResult> {
  const { title, content, created_at, test_run } = input;

  log.info({ title, test_run }, 'Processing ingest request');

  // Generate content hash for duplicate detection
  const contentHash = createHash('sha256')
    .update(title + content)
    .digest('hex');

  // Check for duplicate
  const existing = findByContentHash(contentHash);

  if (existing) {
    log.info({ title, existingId: existing.id }, 'Duplicate detected');
    return { duplicate: true, existingId: existing.id };
  }

  // Extract tags from content
  const tags = content.match(/#\w+/g) || [];

  // Insert note
  const createdAt = created_at || new Date().toISOString();
  const id = insertNote({
    title,
    content,
    contentHash,
    tags,
    createdAt,
    testRun: test_run,
  });

  // Calendar enrichment (best-effort, never blocks ingestion)
  try {
    const calendarResult = await queryCalendar(createdAt);
    if (calendarResult && calendarResult.events.length > 0) {
      const bestEvent = pickBestEvent(calendarResult.events);
      if (bestEvent) {
        updateCalendarEvent(id, bestEvent);
        log.info({ id, event: bestEvent.title, matchType: calendarResult.matchType }, 'Calendar event linked');
      }
    }
  } catch (err) {
    log.warn({ id, err }, 'Calendar enrichment failed (best-effort)');
  }

  log.info({ id, title, tags }, 'Note ingested successfully');

  return { id, duplicate: false };
}

// CLI entry point
if (require.main === module) {
  console.log('Ingest workflow - call via server or import as module');
  console.log('Usage: Import { ingest } from this file');
}
```

**Step 3: Check if `src/lib/index.ts` barrel file exists and add export**

```bash
cat src/lib/index.ts
```

If it exists, add: `export { updateCalendarEvent } from './db';`
Also add: `export { queryCalendar, pickBestEvent } from './calendar';`

**Step 4: Verify TypeScript compiles**

```bash
npx tsc --noEmit
```

Expected: No errors.

**Step 5: Build the CLI in release mode (ingest.ts references release path)**

```bash
cd SeleneChat && swift build -c release --product selene-calendar
```

**Step 6: Test ingestion end-to-end**

```bash
TEST_RUN="test-calendar-$(date +%Y%m%d-%H%M%S)"
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | grep AUTH_TOKEN | cut -d= -f2)" \
  -d "{\"title\": \"Calendar test\", \"content\": \"Testing calendar linking\", \"test_run\": \"$TEST_RUN\"}"
```

Then verify:

```bash
sqlite3 ~/selene-data/selene.db "SELECT id, title, calendar_event FROM raw_notes WHERE test_run LIKE 'test-calendar%'"
```

Expected: If there's a calendar event now, `calendar_event` should have JSON. If not, it should be NULL.

**Step 7: Cleanup test data**

```bash
./scripts/cleanup-tests.sh "$TEST_RUN"
```

**Step 8: Commit**

```bash
git add src/lib/calendar.ts src/workflows/ingest.ts src/lib/db.ts src/lib/index.ts src/types/index.ts
git commit -m "feat: calendar enrichment at ingestion time"
```

---

### Task 6: SeleneShared Note Model — Add `calendarEvent` Field

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Models/Note.swift`

**Step 1: Add the CalendarEvent struct to Note.swift**

Before the `Note` struct (before line 3), add:

```swift
public struct CalendarEventContext: Codable, Hashable {
    public let title: String
    public let startDate: String
    public let endDate: String
    public let calendar: String
    public let isAllDay: Bool

    public init(title: String, startDate: String, endDate: String, calendar: String, isAllDay: Bool) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendar = calendar
        self.isAllDay = isAllDay
    }

    /// Formatted time range like "5:00–7:00 PM"
    public var formattedTimeRange: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        guard let start = isoFormatter.date(from: startDate),
              let end = isoFormatter.date(from: endDate) else {
            return ""
        }

        return "\(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }
}
```

**Step 2: Add `calendarEvent` field to Note struct**

After `energyLevel` (line 30), add:

```swift
    public var calendarEvent: CalendarEventContext?
```

**Step 3: Add to CodingKeys**

After `case energyLevel = "energy_level"` (line 55), add:

```swift
        case calendarEvent = "calendar_event"
```

**Step 4: Add to init parameters**

After `energyLevel: String? = nil` (line 83), add:

```swift
        calendarEvent: CalendarEventContext? = nil
```

**Step 5: Add to init body**

After `self.energyLevel = energyLevel` (line 109), add:

```swift
        self.calendarEvent = calendarEvent
```

**Step 6: Add to mock**

After `energyLevel: String? = nil` (line 181 in the mock), add:

```swift
        calendarEvent: CalendarEventContext? = nil
```

And in the mock's `Note(` call, after `energyLevel: energyLevel` (line 208), add:

```swift
            calendarEvent: calendarEvent
```

**Step 7: Add custom Codable decode for calendar_event (it's stored as a JSON string in SQLite)**

The `calendar_event` column stores a JSON string, not a nested object. We need a custom decoder. Add to the Note struct, after the init:

```swift
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        sourceType = try container.decode(String.self, forKey: .sourceType)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        characterCount = try container.decode(Int.self, forKey: .characterCount)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        processedAt = try container.decodeIfPresent(Date.self, forKey: .processedAt)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt)
        status = try container.decode(String.self, forKey: .status)
        exportedToObsidian = try container.decode(Bool.self, forKey: .exportedToObsidian)
        sourceUUID = try container.decodeIfPresent(String.self, forKey: .sourceUUID)
        testRun = try container.decodeIfPresent(String.self, forKey: .testRun)
        concepts = try container.decodeIfPresent([String].self, forKey: .concepts)
        conceptConfidence = try container.decodeIfPresent([String: Double].self, forKey: .conceptConfidence)
        primaryTheme = try container.decodeIfPresent(String.self, forKey: .primaryTheme)
        secondaryThemes = try container.decodeIfPresent([String].self, forKey: .secondaryThemes)
        themeConfidence = try container.decodeIfPresent(Double.self, forKey: .themeConfidence)
        overallSentiment = try container.decodeIfPresent(String.self, forKey: .overallSentiment)
        sentimentScore = try container.decodeIfPresent(Double.self, forKey: .sentimentScore)
        emotionalTone = try container.decodeIfPresent(String.self, forKey: .emotionalTone)
        energyLevel = try container.decodeIfPresent(String.self, forKey: .energyLevel)

        // calendar_event is stored as a JSON string in SQLite, so try decoding from string first
        if let jsonString = try container.decodeIfPresent(String.self, forKey: .calendarEvent),
           let data = jsonString.data(using: .utf8) {
            calendarEvent = try? JSONDecoder().decode(CalendarEventContext.self, from: data)
        } else {
            calendarEvent = try container.decodeIfPresent(CalendarEventContext.self, forKey: .calendarEvent)
        }
    }
```

**Step 8: Build**

```bash
cd SeleneChat && swift build
```

Expected: Build succeeds.

**Step 9: Run tests to verify nothing is broken**

```bash
cd SeleneChat && swift test
```

Expected: All existing tests pass (calendarEvent is optional with nil default, so nothing breaks).

**Step 10: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Models/Note.swift
git commit -m "feat: add CalendarEventContext to Note model"
```

---

### Task 7: DatabaseService — Read `calendar_event` Column

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift`

**Step 1: Add the column expression**

After the existing column expressions (around line 50 area, near other raw_notes columns), add:

```swift
    private let calendarEvent = Expression<String?>("calendar_event")
```

**Step 2: Update `parseNote(from:)` to read `calendar_event`**

In the `parseNote` function (line 520), add calendar event parsing before the `return Note(` call. After the secondaryThemes parsing (after line 543), add:

```swift
        // Parse calendar event JSON from raw_notes (may be NULL)
        var calendarEventContext: CalendarEventContext? = nil
        if let calendarStr = try? row.get(rawNotes[calendarEvent]),
           let data = calendarStr.data(using: .utf8) {
            calendarEventContext = try? JSONDecoder().decode(CalendarEventContext.self, from: data)
        }
```

Then add `calendarEvent: calendarEventContext` to the Note initializer call (after `energyLevel:` on line 570):

```swift
            calendarEvent: calendarEventContext
```

**Step 3: Build and test**

```bash
cd SeleneChat && swift build && swift test
```

Expected: All tests pass.

**Step 4: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Services/DatabaseService.swift
git commit -m "feat: read calendar_event in DatabaseService"
```

---

### Task 8: SeleneChat UI — Display Calendar Tag

**Files:**
- Modify: `SeleneChat/Sources/SeleneChat/Views/SearchView.swift`

**Step 1: Add calendar tag to `NoteRow` (list view)**

In the `NoteRow` struct (line 263), after the HStack containing theme and date (lines 292-307), add the calendar tag. After the theme pill and before `Spacer()` on line 302:

```swift
                if let event = note.calendarEvent {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                        Text(event.title)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
                }
```

**Step 2: Add calendar tag to `NoteDetailView` (detail view)**

In the metadata section of NoteDetailView (around line 387), after the sentiment row (line 402) and before the concepts section (line 404), add:

```swift
                    if let event = note.calendarEvent {
                        HStack {
                            Text("Calendar")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("\(event.title) \u{00B7} \(event.formattedTimeRange)")
                                    .font(.caption)
                            }
                        }
                    }
```

**Step 3: Build**

```bash
cd SeleneChat && swift build
```

Expected: Build succeeds.

**Step 4: Commit**

```bash
git add SeleneChat/Sources/SeleneChat/Views/SearchView.swift
git commit -m "feat: display calendar event tag on notes"
```

---

### Task 9: AI Context Builder — Include Calendar Context

**Files:**
- Modify: `SeleneChat/Sources/SeleneShared/Services/ContextBuilder.swift`

**Step 1: Add calendar context to `buildFullContext`**

In `buildFullContext` (line 95), after the note title line (line 99), add:

```swift
            if let event = note.calendarEvent {
                context += "Calendar Context: Written during \"\(event.title)\" (\(event.formattedTimeRange))\n"
            }
```

**Step 2: Add calendar context to `buildSummaryContext`**

In `buildSummaryContext` (line 68), after the content preview (line 77), add:

```swift
            if let event = note.calendarEvent {
                context += "- Calendar: \(event.title) (\(event.formattedTimeRange))\n"
            }
```

**Step 3: Add calendar context to `buildMetadataContext`**

In `buildMetadataContext` (line 38), after the energy line (line 57), add:

```swift
            if let event = note.calendarEvent {
                context += "- Calendar: \(event.title)\n"
            }
```

**Step 4: Build and test**

```bash
cd SeleneChat && swift build && swift test
```

Expected: All tests pass.

**Step 5: Commit**

```bash
git add SeleneChat/Sources/SeleneShared/Services/ContextBuilder.swift
git commit -m "feat: include calendar context in AI prompts"
```

---

### Task 10: SeleneMobile — Display Calendar Tag

**Files:**
- Explore SeleneMobile note rendering and add calendar tag where appropriate.

Note: SeleneMobile gets note data via the REST API. Since `calendar_event` is now in the `raw_notes` table and the API uses `SELECT *`, the data flows automatically. The Note model in SeleneShared already has the field. We just need to render it.

**Step 1: Find where SeleneMobile renders note details**

Check `SeleneChat/Sources/SeleneMobile/Views/` for note display components. The calendar tag should match the same pattern used in NoteRow for SeleneChat.

**Step 2: Add the tag**

Follow the same pattern as Task 8 — a subtle `HStack` with calendar icon, event title, muted color, small font.

**Step 3: Build for iOS**

```bash
cd SeleneChat && swift build --product SeleneMobile
```

**Step 4: Commit**

```bash
git add SeleneChat/Sources/SeleneMobile/
git commit -m "feat: display calendar tag in SeleneMobile"
```

---

### Task 11: Build Release Binary and Final Integration Test

**Files:**
- No new files

**Step 1: Build selene-calendar in release mode**

```bash
cd SeleneChat && swift build -c release --product selene-calendar
```

**Step 2: Verify the binary is at the expected path**

```bash
ls -la SeleneChat/.build/release/selene-calendar
```

**Step 3: Run full integration test**

```bash
TEST_RUN="test-calendar-final-$(date +%Y%m%d-%H%M%S)"
curl -X POST http://localhost:5678/webhook/api/drafts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $(cat .env | grep AUTH_TOKEN | cut -d= -f2)" \
  -d "{\"title\": \"Final calendar test\", \"content\": \"Integration test for calendar linking\", \"test_run\": \"$TEST_RUN\"}"
```

Check result:

```bash
sqlite3 ~/selene-data/selene.db "SELECT id, title, calendar_event FROM raw_notes WHERE test_run LIKE 'test-calendar-final%'"
```

Check server logs:

```bash
tail -20 logs/selene.log | npx pino-pretty
```

Look for "Calendar event linked" or "Calendar enrichment failed" log entries.

**Step 4: Build and install SeleneChat app**

```bash
cd SeleneChat && ./build-app.sh && cp -R .build/release/SeleneChat.app /Applications/
```

**Step 5: Cleanup test data**

```bash
./scripts/cleanup-tests.sh "$TEST_RUN"
```

**Step 6: Run all tests one final time**

```bash
cd SeleneChat && swift test
```

Expected: All tests pass.

**Step 7: Commit any remaining changes**

If anything was adjusted during integration testing, commit it.
