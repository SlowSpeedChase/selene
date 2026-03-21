import SeleneShared
import Foundation

/// Pure functions for processing briefing data.
/// These have no database dependency, making them easy to test.
enum BriefingDataService {

    /// Group notes by their thread assignment.
    ///
    /// Notes without a thread mapping are placed under "Uncategorized".
    /// Returns a dictionary keyed by thread name, with values being arrays of (note, threadId) tuples.
    static func groupNotesByThread(
        _ notes: [Note],
        threadMap: [Int: (threadName: String, threadId: Int64)]
    ) -> [String: [(note: Note, threadId: Int64)]] {
        var result: [String: [(note: Note, threadId: Int64)]] = [:]

        for note in notes {
            if let mapping = threadMap[note.id] {
                result[mapping.threadName, default: []].append((note: note, threadId: mapping.threadId))
            } else {
                result["Uncategorized", default: []].append((note: note, threadId: -1))
            }
        }

        return result
    }

    /// Identify threads that haven't had activity in the specified number of days.
    ///
    /// Threads with nil `lastActivityAt` are considered stalled.
    static func identifyStalledThreads(_ threads: [Thread], staleDays: Int = 5) -> [Thread] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -staleDays, to: Date()) ?? Date()

        return threads.filter { thread in
            guard let lastActivity = thread.lastActivityAt else {
                // No activity recorded means it's stalled
                return true
            }
            return lastActivity < cutoff
        }
    }

    /// Filter association pairs to only include cross-thread pairs.
    ///
    /// Both notes in a pair must have thread mappings, and the threads must be different.
    /// Pairs where either note has no thread mapping are excluded.
    static func filterCrossThreadPairs(
        _ pairs: [(noteAId: Int, noteBId: Int, similarity: Double)],
        noteThreadMap: [Int: Int64]
    ) -> [(noteAId: Int, noteBId: Int, similarity: Double)] {
        return pairs.filter { pair in
            guard let threadA = noteThreadMap[pair.noteAId],
                  let threadB = noteThreadMap[pair.noteBId] else {
                return false
            }
            return threadA != threadB
        }
    }
}
