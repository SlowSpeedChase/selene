import SeleneShared
// SeleneChat/Sources/Views/BriefingCardView.swift
import SwiftUI

/// An expandable card component for briefing items.
/// Shows a compact collapsed row and expands to reveal detail content on tap.
struct BriefingCardView: View {
    let card: BriefingCard
    var onDiscuss: (BriefingCard) -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @State private var isExpanded = false

    // Lazy-loaded detail data
    @State private var notePreview: String?
    @State private var concepts: [String]?
    @State private var threadSummary: String?
    @State private var threadWhy: String?
    @State private var recentNoteTitles: [String] = []
    @State private var openTaskTitles: [String] = []
    @State private var noteAPreview: String?
    @State private var noteBPreview: String?
    @State private var hasLoadedDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsed row (always visible)
            collapsedRow
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                    if isExpanded && !hasLoadedDetail {
                        loadDetailData()
                    }
                }

            // Expanded content
            if isExpanded {
                expandedContent
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    // MARK: - Collapsed Row

    @ViewBuilder
    private var collapsedRow: some View {
        HStack(spacing: 6) {
            switch card.cardType {
            case .whatChanged:
                whatChangedCollapsed

            case .needsAttention:
                needsAttentionCollapsed

            case .connection:
                connectionCollapsed
            }

            Spacer()

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var whatChangedCollapsed: some View {
        HStack(spacing: 6) {
            if let title = card.noteTitle {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            if let threadName = card.threadName {
                Text("·")
                    .foregroundColor(.secondary)
                Text(threadName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if let date = card.date {
                Text("·")
                    .foregroundColor(.secondary)
                Text(relativeDate(date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !card.energyEmoji.isEmpty {
                Text(card.energyEmoji)
                    .font(.caption)
            }
        }
    }

    private var needsAttentionCollapsed: some View {
        HStack(spacing: 6) {
            if let threadName = card.threadName {
                Text(threadName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            if let reason = card.reason {
                Text("·")
                    .foregroundColor(.secondary)
                Text(reason)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
        }
    }

    private var connectionCollapsed: some View {
        HStack(spacing: 6) {
            if let noteA = card.noteATitle {
                Text(noteA)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }

            Text("\u{2194}")
                .foregroundColor(.secondary)

            if let noteB = card.noteBTitle {
                Text(noteB)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            switch card.cardType {
            case .whatChanged:
                whatChangedExpanded

            case .needsAttention:
                needsAttentionExpanded

            case .connection:
                connectionExpanded
            }

            // "Discuss" action button
            Button(action: { onDiscuss(card) }) {
                Label("Discuss this with Selene", systemImage: "message")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
    }

    private var whatChangedExpanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Note content preview
            if let preview = notePreview {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }

            // Concept tags
            if let tags = concepts, !tags.isEmpty {
                conceptTagsView(tags)
            }

            // Thread summary
            if let summary = threadSummary {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var needsAttentionExpanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thread why
            if let why = threadWhy {
                Text(why)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Thread summary
            if let summary = threadSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Recent note titles
            if !recentNoteTitles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent notes:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(recentNoteTitles.prefix(3), id: \.self) { title in
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // Open task titles
            if !openTaskTitles.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open tasks:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    ForEach(openTaskTitles.prefix(3), id: \.self) { title in
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private var connectionExpanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Explanation text
            if let explanation = card.explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            // Note A preview
            if let preview = noteAPreview {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = card.noteATitle {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            // Note B preview
            if let preview = noteBPreview {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = card.noteBTitle {
                        Text(title)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Concept Tags

    private func conceptTagsView(_ tags: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(5), id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Data Loading

    private func loadDetailData() {
        hasLoadedDetail = true

        Task {
            switch card.cardType {
            case .whatChanged:
                await loadWhatChangedDetail()

            case .needsAttention:
                await loadNeedsAttentionDetail()

            case .connection:
                await loadConnectionDetail()
            }
        }
    }

    private func loadWhatChangedDetail() async {
        // Load note content preview
        if let noteId = card.noteId {
            if let note = try? await databaseService.getNote(byId: noteId) {
                await MainActor.run {
                    notePreview = String(note.content.prefix(300))
                    concepts = note.concepts
                }
            }
        }

        // Load thread summary
        if let threadId = card.threadId {
            if let thread = try? await databaseService.getThreadById(threadId) {
                await MainActor.run {
                    threadSummary = thread.summary
                }
            }
        }
    }

    private func loadNeedsAttentionDetail() async {
        guard let threadId = card.threadId else { return }

        // Load thread details
        if let thread = try? await databaseService.getThreadById(threadId) {
            await MainActor.run {
                threadWhy = thread.why
                threadSummary = thread.summary
            }
        }

        // Load recent note titles for this thread
        if let result = try? await databaseService.getThreadByName(card.threadName ?? "") {
            let titles = result.1.prefix(3).map { $0.title }
            await MainActor.run {
                recentNoteTitles = titles
            }
        }

        // Load open task titles
        let tasks = (try? await databaseService.getTasksForThread(threadId)) ?? []
        let openTasks = tasks.filter { !$0.isCompleted }
        let titles = openTasks.prefix(3).map { $0.title ?? $0.thingsTaskId }
        await MainActor.run {
            openTaskTitles = titles
        }
    }

    private func loadConnectionDetail() async {
        // Load note A preview
        if let noteAId = card.noteAId {
            if let note = try? await databaseService.getNote(byId: noteAId) {
                await MainActor.run {
                    noteAPreview = String(note.content.prefix(200))
                }
            }
        }

        // Load note B preview
        if let noteBId = card.noteBId {
            if let note = try? await databaseService.getNote(byId: noteBId) {
                await MainActor.run {
                    noteBPreview = String(note.content.prefix(200))
                }
            }
        }
    }

    // MARK: - Helpers

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
