import SeleneShared
import SwiftUI

struct TodayView: View {
    @StateObject private var viewModel = TodayViewModel()
    @EnvironmentObject var databaseService: DatabaseService

    var onThreadSelected: ((ThreadSummary) -> Void)?
    var onNoteThreadTap: ((NoteWithThread) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Content
            if viewModel.isLoading && viewModel.newCaptures.isEmpty {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if viewModel.isEmpty {
                emptyStateView
            } else {
                columnsView
            }
        }
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { Task { await viewModel.refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            }
        }
        .onAppear {
            if let db = databaseService.db {
                viewModel.configure(with: db)
            }
            Task {
                await viewModel.refresh()
                viewModel.recordAppOpen()
            }
        }
    }

    // MARK: - Columns

    private var columnsView: some View {
        HStack(alignment: .top, spacing: 20) {
            // Left: New Captures
            NewCapturesColumn(
                notes: viewModel.newCaptures,
                onNoteTap: { note in
                    // TODO: Open note detail
                },
                onThreadTap: { note in
                    onNoteThreadTap?(note)
                }
            )

            // Right: Heating Up
            HeatingUpColumn(
                threads: viewModel.heatingUpThreads,
                onThreadTap: { thread in
                    onThreadSelected?(thread)
                }
            )
        }
        .padding()
    }

    // MARK: - States

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading...")
            Spacer()
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.orange)
            Text("Couldn't load today's view")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            Spacer()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("All caught up")
                .font(.title2)
                .fontWeight(.semibold)
            Text("No new notes since yesterday, and no threads are heating up right now.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            HStack(spacing: 20) {
                Button("Capture a thought") {
                    // TODO: Open Drafts
                }
                Button("Browse past notes") {
                    // TODO: Navigate to Search
                }
            }
            Spacer()
        }
    }
}

// MARK: - New Captures Column

struct NewCapturesColumn: View {
    let notes: [NoteWithThread]
    let onNoteTap: (NoteWithThread) -> Void
    let onThreadTap: (NoteWithThread) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW CAPTURES")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if notes.isEmpty {
                emptyState
            } else {
                ForEach(notes) { note in
                    NoteCaptureCard(
                        note: note,
                        onTap: { onNoteTap(note) },
                        onThreadTap: { onThreadTap(note) }
                    )
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No new notes since yesterday")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Note Card

struct NoteCaptureCard: View {
    let note: NoteWithThread
    let onTap: () -> Void
    let onThreadTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title row
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(note.relativeTime)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Preview
            Text(note.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Thread link
            if let threadName = note.threadName {
                Button(action: onThreadTap) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                        Text("🔥")
                        Text(threadName)
                    }
                    .font(.caption)
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Heating Up Column

struct HeatingUpColumn: View {
    let threads: [ThreadSummary]
    let onThreadTap: (ThreadSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HEATING UP")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            if threads.isEmpty {
                emptyState
            } else {
                ForEach(threads) { thread in
                    ThreadCard(thread: thread)
                        .onTapGesture { onThreadTap(thread) }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No threads heating up right now")
                .foregroundColor(.secondary)
            Text("Threads gain momentum when you add notes to the same line of thinking.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Thread Card

struct ThreadCard: View {
    let thread: ThreadSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("🔥")
                Text(thread.name)
                    .font(.headline)
                Spacer()
                Text("\(thread.noteCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Summary
            if !thread.summary.isEmpty {
                Text(thread.summaryPreview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Recent notes
            if !thread.recentNoteTitles.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(thread.recentNoteTitles, id: \.self) { title in
                        HStack(spacing: 4) {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(title)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}
