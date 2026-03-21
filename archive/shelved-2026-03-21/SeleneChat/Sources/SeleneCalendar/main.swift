import EventKit
import Foundation

// MARK: - Output Types

struct CalendarEvent: Codable {
    let title: String
    let startDate: String
    let endDate: String
    let calendar: String
    let isAllDay: Bool
}

struct CalendarOutput: Codable {
    let events: [CalendarEvent]
    let matchType: String
}

// MARK: - Date Formatting

let iso8601Output: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

// MARK: - Helpers

func exitWithError(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

func parseISO8601(_ string: String) -> Date? {
    // Try with fractional seconds and timezone first
    let withFractional = ISO8601DateFormatter()
    withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = withFractional.date(from: string) {
        return date
    }

    // Try standard ISO 8601 with timezone
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    if let date = standard.date(from: string) {
        return date
    }

    // Try without timezone (assume local)
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")

    // With fractional seconds, no timezone
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    if let date = dateFormatter.date(from: string) {
        return date
    }

    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
    if let date = dateFormatter.date(from: string) {
        return date
    }

    // Without fractional seconds, no timezone
    dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let date = dateFormatter.date(from: string) {
        return date
    }

    return nil
}

func formatEvent(_ event: EKEvent) -> CalendarEvent {
    CalendarEvent(
        title: event.title ?? "(no title)",
        startDate: iso8601Output.string(from: event.startDate),
        endDate: iso8601Output.string(from: event.endDate),
        calendar: event.calendar.title,
        isAllDay: event.isAllDay
    )
}

// MARK: - Argument Parsing

let args = CommandLine.arguments

guard args.count == 3, args[1] == "--at" else {
    exitWithError("Usage: selene-calendar --at <ISO8601-timestamp>")
}

guard let queryDate = parseISO8601(args[2]) else {
    exitWithError("Error: Could not parse date '\(args[2])'. Expected ISO 8601 format (e.g., 2026-02-19T17:30:00)")
}

// MARK: - EventKit Query

let store = EKEventStore()
let semaphore = DispatchSemaphore(value: 0)
var accessGranted = false

store.requestFullAccessToEvents { granted, error in
    if let error = error {
        FileHandle.standardError.write(Data("Calendar access error: \(error.localizedDescription)\n".utf8))
    }
    accessGranted = granted
    semaphore.signal()
}

semaphore.wait()

guard accessGranted else {
    exitWithError("Error: Calendar access not granted. Open System Settings > Privacy & Security > Calendars and grant access.")
}

// Query window: 30 minutes before timestamp to just after timestamp
let windowStart = queryDate.addingTimeInterval(-30 * 60)
let windowEnd = queryDate.addingTimeInterval(1) // just after

let predicate = store.predicateForEvents(withStart: windowStart, end: windowEnd, calendars: nil)
let allEvents = store.events(matching: predicate)

// Filter out all-day events
let events = allEvents.filter { !$0.isAllDay }

// MARK: - Determine Match Type

var matchType = "none"

for event in events {
    // "during": event started before or at queryDate AND ends after queryDate
    if event.startDate <= queryDate && event.endDate > queryDate {
        matchType = "during"
        break
    }
    // "just_ended": event ended within 30 min before queryDate (but after windowStart)
    if event.endDate <= queryDate && event.endDate > windowStart {
        if matchType != "during" {
            matchType = "just_ended"
        }
    }
}

// MARK: - Output JSON

let output = CalendarOutput(
    events: events.map(formatEvent),
    matchType: matchType
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

guard let jsonData = try? encoder.encode(output),
      let jsonString = String(data: jsonData, encoding: .utf8) else {
    exitWithError("Error: Failed to encode JSON output")
}

print(jsonString)
