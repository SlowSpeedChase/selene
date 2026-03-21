import Foundation

public enum NoteType: String, CaseIterable, Codable {
    case quickTask = "quick_task"
    case relatesToProject = "relates_to_project"
    case newProject = "new_project"
    case reflection = "reflection"

    public var displayName: String {
        switch self {
        case .quickTask: return "Quick task"
        case .relatesToProject: return "Relates to project"
        case .newProject: return "New project idea"
        case .reflection: return "Reflection"
        }
    }

    public var icon: String {
        switch self {
        case .quickTask: return "checklist"
        case .relatesToProject: return "link"
        case .newProject: return "plus.rectangle.on.folder"
        case .reflection: return "bubble.left.and.text.bubble.right"
        }
    }

    public var emoji: String {
        switch self {
        case .quickTask: return "\u{1F4CB}"
        case .relatesToProject: return "\u{1F517}"
        case .newProject: return "\u{1F195}"
        case .reflection: return "\u{1F4AD}"
        }
    }
}
