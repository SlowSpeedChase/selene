import SeleneShared
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

    init(maxActions: Int = 50) {
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
