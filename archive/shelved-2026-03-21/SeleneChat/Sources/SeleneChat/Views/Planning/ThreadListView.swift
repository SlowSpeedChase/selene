import SeleneShared
// ThreadListView.swift
// SeleneChat
//
// Phase 7.2: Planning Tab Redesign
// Displays threads inside a project

import SwiftUI

struct ThreadListView: View {
    let projectId: Int
    let onSelectThread: (DiscussionThread) -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @State private var threads: [DiscussionThread] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if threads.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(threads, id: \.id) { thread in
                        ThreadRow(thread: thread)
                            .onTapGesture {
                                onSelectThread(thread)
                            }
                    }
                }
                .padding()
            }
        }
        .task {
            await loadThreads()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No threads yet")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Start a conversation to create a thread")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func loadThreads() async {
        isLoading = true
        defer { isLoading = false }

        do {
            threads = try await databaseService.fetchThreadsForProject(projectId)
        } catch {
            #if DEBUG
            print("[ThreadListView] Error loading threads: \(error)")
            #endif
        }
    }
}

struct ThreadRow: View {
    let thread: DiscussionThread

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: thread.status.icon)
                .foregroundColor(statusColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                // Thread name or prompt preview
                Text(displayName)
                    .font(.body)
                    .lineLimit(1)

                // Metadata
                HStack(spacing: 8) {
                    Label(thread.threadType.displayName, systemImage: thread.threadType.icon)
                    Text("\u{2022}")
                    Text(thread.timeSinceCreated)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Review badge if needed
            if thread.status == .review {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.orange)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    private var displayName: String {
        if let name = thread.threadName, !name.isEmpty {
            return name
        }
        let preview = thread.prompt.prefix(50)
        return preview.count < thread.prompt.count ? "\(preview)..." : String(preview)
    }

    private var statusColor: Color {
        switch thread.status {
        case .pending: return .gray
        case .active: return .blue
        case .completed: return .green
        case .dismissed: return .secondary
        case .review: return .orange
        }
    }
}
