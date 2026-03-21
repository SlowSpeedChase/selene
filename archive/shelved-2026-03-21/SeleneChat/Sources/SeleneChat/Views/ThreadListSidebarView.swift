import SeleneShared
// ThreadListSidebarView.swift
// SeleneChat
//
// First-class sidebar view for browsing all active threads.
// Shows thread cards with name, momentum, summary, and note count.

import SwiftUI

struct ThreadListSidebarView: View {
    var onThreadSelected: (Int64) -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @State private var threads: [Thread] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Threads")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { Task { await loadThreads() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding()

            Divider()

            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading threads...")
                    Spacer()
                }
            } else if let error = error {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Couldn't load threads")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Try Again") {
                        Task { await loadThreads() }
                    }
                    Spacer()
                }
            } else if threads.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "flame")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No active threads")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Threads appear as you capture notes around recurring topics")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(threads) { thread in
                            ThreadListRow(thread: thread)
                                .onTapGesture {
                                    onThreadSelected(thread.id)
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadThreads()
        }
    }

    private func loadThreads() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            threads = try await databaseService.getActiveThreads(limit: 20)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Thread List Row

struct ThreadListRow: View {
    let thread: Thread

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Name + momentum
            HStack {
                Text(thread.statusEmoji)
                Text(thread.name)
                    .font(.headline)
                Spacer()
                momentumIndicator(thread.momentumScore)
            }

            // Summary preview
            if let summary = thread.summary, !summary.isEmpty {
                Text(String(summary.prefix(120)))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Metadata
            HStack(spacing: 16) {
                Label("\(thread.noteCount) notes", systemImage: "note.text")
                Label(thread.lastActivityDisplay, systemImage: "clock")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    private func momentumIndicator(_ score: Double?) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { i in
                Circle()
                    .fill(i < Int((score ?? 0) * 5) ? Color.orange : Color.gray.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }
}
