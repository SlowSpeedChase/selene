import SeleneShared
// ProjectDetailView.swift
// SeleneChat
//
// Created for Phase 7: Planning Inbox Redesign
// Placeholder for project detail view - will be implemented in future task

import SwiftUI

struct ProjectDetailView: View {
    let project: Project
    let onBack: () -> Void
    let onSelectThread: (DiscussionThread) -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @State private var showNewThreadSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                // Status badge
                HStack(spacing: 4) {
                    Image(systemName: project.status.icon)
                    Text(project.status.rawValue.capitalized)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.1))
                .foregroundColor(statusColor)
                .cornerRadius(6)

                Spacer()

                // Placeholder for future actions
                Menu {
                    Button("Park Project", systemImage: "parkingsign") {}
                    Button("Complete Project", systemImage: "checkmark.circle") {}
                    Divider()
                    Button("Delete Project", systemImage: "trash", role: .destructive) {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Project info
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(project.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                // Metadata
                HStack(spacing: 16) {
                    if let concept = project.primaryConcept {
                        Label(concept, systemImage: "tag")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Label("\(project.noteCount) notes", systemImage: "doc")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let timeSince = project.timeSinceActive {
                        Label(timeSince, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            // Threads section
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .foregroundColor(.blue)
                    Text("Threads")
                        .font(.headline)
                    Text("(\(project.threadCount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: { showNewThreadSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                ScrollView {
                    ThreadListView(projectId: project.id) { thread in
                        onSelectThread(thread)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewThreadSheet) {
            NewThreadSheet(
                projectId: project.id,
                projectName: project.name,
                onCreate: { thread in
                    showNewThreadSheet = false
                    onSelectThread(thread)
                },
                onCancel: {
                    showNewThreadSheet = false
                }
            )
        }
        .onAppear {
            #if DEBUG
            DebugLogger.shared.log(.nav, "Appeared: ProjectDetailView - \(project.name)")
            ActionTracker.shared.track(action: "viewAppeared", params: ["view": "ProjectDetailView", "projectId": "\(project.id)"])
            #endif
        }
    }

    private var statusColor: Color {
        switch project.status {
        case .active: return .orange
        case .parked: return .gray
        case .completed: return .green
        }
    }
}
