#if os(iOS)
import ActivityKit
import Foundation

/// ActivityAttributes for Selene chat processing Live Activities.
/// Shows query status on the Dynamic Island and Lock Screen.
struct SeleneChatActivity: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Current processing status (e.g. "Searching notes...", "Thinking...", "Complete")
        var status: String
        /// Progress from 0.0 to 1.0
        var progress: Double
    }

    /// Truncated user query displayed in the Live Activity
    var queryPreview: String
}

// MARK: - LiveActivityManager

/// Manages the lifecycle of Live Activities for chat processing.
/// Starts an activity when a query begins, updates status during processing,
/// and ends the activity when the response arrives or an error occurs.
@MainActor
final class LiveActivityManager {

    private var currentActivity: Activity<SeleneChatActivity>?

    /// Start a new Live Activity for a chat query.
    /// - Parameter query: The user's query text (will be truncated for display)
    func startActivity(query: String) async {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // End any existing activity before starting a new one
        await endActivity()

        let truncatedQuery = String(query.prefix(60)) + (query.count > 60 ? "..." : "")

        let attributes = SeleneChatActivity(queryPreview: truncatedQuery)
        let initialState = SeleneChatActivity.ContentState(
            status: "Searching notes...",
            progress: 0.2
        )

        do {
            let activity = try Activity<SeleneChatActivity>.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            // Live Activity creation failed -- not critical, continue without it
            currentActivity = nil
        }
    }

    /// Update the current Live Activity with new status and progress.
    /// - Parameters:
    ///   - status: Description of current processing step
    ///   - progress: Progress value from 0.0 to 1.0
    func updateActivity(status: String, progress: Double) async {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = currentActivity else { return }

        let updatedState = SeleneChatActivity.ContentState(
            status: status,
            progress: min(1.0, max(0.0, progress))
        )

        await activity.update(
            ActivityContent(state: updatedState, staleDate: nil)
        )
    }

    /// End the current Live Activity.
    /// Shows "Complete" briefly before dismissing.
    func endActivity() async {
        guard #available(iOS 16.2, *) else { return }
        guard let activity = currentActivity else { return }

        let finalState = SeleneChatActivity.ContentState(
            status: "Complete",
            progress: 1.0
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .after(.now + 4)
        )

        currentActivity = nil
    }
}

#endif
