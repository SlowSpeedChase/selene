import SwiftUI
import SeleneShared

struct MobileThreadsView: View {
    let dataProvider: DataProvider
    let llmProvider: LLMProvider
    @State private var threads: [SeleneShared.Thread] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading threads...")
                } else if threads.isEmpty {
                    ContentUnavailableView(
                        "No Active Threads",
                        systemImage: "circle.hexagongrid",
                        description: Text("Threads emerge when 3+ related notes cluster together.")
                    )
                } else {
                    List(threads) { thread in
                        NavigationLink(destination: MobileThreadDetailView(
                            thread: thread, dataProvider: dataProvider, llmProvider: llmProvider
                        )) {
                            ThreadRow(thread: thread)
                        }
                    }
                    .refreshable { await loadThreads() }
                }
            }
            .navigationTitle("Threads")
            .task { await loadThreads() }
        }
    }

    private func loadThreads() async {
        isLoading = threads.isEmpty
        do {
            threads = try await dataProvider.getActiveThreads(limit: 20)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct ThreadRow: View {
    let thread: SeleneShared.Thread

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(thread.name)
                    .font(.headline)
                Spacer()
                Text(thread.statusEmoji)
            }

            HStack(spacing: 12) {
                Label("\(thread.noteCount)", systemImage: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(thread.momentumDisplay, systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(thread.lastActivityDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let summary = thread.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

struct MobileThreadDetailView: View {
    let thread: SeleneShared.Thread
    let dataProvider: DataProvider
    let llmProvider: LLMProvider
    @State private var notes: [Note] = []
    @State private var tasks: [ThreadTask] = []
    @State private var isLoading = true

    var body: some View {
        List {
            // Thread info section
            Section {
                if let why = thread.why, !why.isEmpty {
                    LabeledContent("Why", value: why)
                }
                LabeledContent("Status", value: "\(thread.status) \(thread.statusEmoji)")
                LabeledContent("Momentum", value: thread.momentumDisplay)
                LabeledContent("Notes", value: "\(thread.noteCount)")
                LabeledContent("Last Activity", value: thread.lastActivityDisplay)
            } header: {
                Text("Overview")
            }

            if let summary = thread.summary {
                Section("Summary") {
                    Text(summary)
                        .font(.subheadline)
                }
            }

            // Tasks section
            if !tasks.isEmpty {
                Section("Tasks") {
                    ForEach(tasks) { task in
                        HStack {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isCompleted ? .green : .secondary)
                            VStack(alignment: .leading) {
                                Text(task.title ?? task.thingsTaskId)
                                    .font(.subheadline)
                                if task.isCompleted {
                                    Text(task.completedDisplay)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            // Notes section
            if !notes.isEmpty {
                Section("Linked Notes (\(notes.count))") {
                    ForEach(notes.prefix(20)) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let event = note.calendarEvent {
                                HStack(spacing: 2) {
                                    Image(systemName: "calendar")
                                    Text(event.title)
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(4)
                            }
                            Text(note.formattedDate)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(note.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(thread.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await loadDetails() }
    }

    private func loadDetails() async {
        do {
            if let (_, threadNotes) = try await dataProvider.getThreadByName(thread.name) {
                notes = threadNotes
            }
            tasks = try await dataProvider.getTasksForThread(thread.id)
        } catch {
            // Graceful degradation - show what we have
        }
        isLoading = false
    }
}
