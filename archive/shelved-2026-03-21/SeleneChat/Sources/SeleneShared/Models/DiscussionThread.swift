import Foundation

public struct DiscussionThread: Identifiable, Hashable {
    public let id: Int
    public let rawNoteId: Int?
    public let threadType: ThreadType
    public var projectId: Int?
    public var threadName: String?
    public let prompt: String
    public var status: Status
    public let createdAt: Date
    public var surfacedAt: Date?
    public var completedAt: Date?
    public let relatedConcepts: [String]?
    public var resurfaceReasonCode: String?      // Raw code like "progress_50", "stuck_3d"
    public var lastResurfacedAt: Date?

    // Associated note content (loaded separately)
    public var noteTitle: String?
    public var noteContent: String?

    public init(
        id: Int,
        rawNoteId: Int?,
        threadType: ThreadType,
        projectId: Int? = nil,
        threadName: String? = nil,
        prompt: String,
        status: Status,
        createdAt: Date,
        surfacedAt: Date? = nil,
        completedAt: Date? = nil,
        relatedConcepts: [String]? = nil,
        resurfaceReasonCode: String? = nil,
        lastResurfacedAt: Date? = nil,
        noteTitle: String? = nil,
        noteContent: String? = nil
    ) {
        self.id = id
        self.rawNoteId = rawNoteId
        self.threadType = threadType
        self.projectId = projectId
        self.threadName = threadName
        self.prompt = prompt
        self.status = status
        self.createdAt = createdAt
        self.surfacedAt = surfacedAt
        self.completedAt = completedAt
        self.relatedConcepts = relatedConcepts
        self.resurfaceReasonCode = resurfaceReasonCode
        self.lastResurfacedAt = lastResurfacedAt
        self.noteTitle = noteTitle
        self.noteContent = noteContent
    }

    public enum ThreadType: String, CaseIterable {
        case planning
        case followup
        case question

        public var displayName: String {
            switch self {
            case .planning: return "Planning"
            case .followup: return "Follow-up"
            case .question: return "Question"
            }
        }

        public var icon: String {
            switch self {
            case .planning: return "list.bullet.clipboard"
            case .followup: return "arrow.uturn.forward"
            case .question: return "questionmark.circle"
            }
        }
    }

    public enum Status: String, CaseIterable {
        case pending
        case active
        case completed
        case dismissed
        case review

        public var icon: String {
            switch self {
            case .pending: return "clock"
            case .active: return "play.circle"
            case .completed: return "checkmark.circle"
            case .dismissed: return "xmark.circle"
            case .review: return "arrow.triangle.2.circlepath"
            }
        }

        public var color: String {
            switch self {
            case .pending: return "gray"
            case .active: return "blue"
            case .completed: return "green"
            case .dismissed: return "secondary"
            case .review: return "orange"
            }
        }
    }

    /// Parsed resurface reason from code
    public var resurfaceReason: ResurfaceReason? {
        guard let code = resurfaceReasonCode else { return nil }
        return ResurfaceReason(from: code)
    }

    public struct ResurfaceReason {
        public let type: ReasonType
        public let message: String

        public enum ReasonType {
            case progress(percent: Int)
            case stuck(days: Int)
            case completion
            case deadline(days: Int)
        }

        public init?(from code: String) {
            if code.starts(with: "progress_") {
                let percentStr = code.replacingOccurrences(of: "progress_", with: "")
                let percent = Int(percentStr) ?? 50
                self.type = .progress(percent: percent)
                self.message = "Good progress! Ready to plan next steps?"
            } else if code.starts(with: "stuck_") {
                let daysStr = code.replacingOccurrences(of: "stuck_", with: "").replacingOccurrences(of: "d", with: "")
                let days = Int(daysStr) ?? 3
                self.type = .stuck(days: days)
                self.message = "This seems stuck. Want to rethink the approach?"
            } else if code == "completion" {
                self.type = .completion
                self.message = "All tasks done! Want to reflect or plan what's next?"
            } else if code.starts(with: "deadline_") {
                let daysStr = code.replacingOccurrences(of: "deadline_", with: "").replacingOccurrences(of: "d", with: "")
                let days = Int(daysStr) ?? 2
                self.type = .deadline(days: days)
                self.message = "Deadline approaching! Review your tasks?"
            } else {
                return nil
            }
        }
    }

    public var timeSinceCreated: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
