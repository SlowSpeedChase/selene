import SeleneShared
// SeleneChat/Sources/Views/Planning/ActiveProjectsList.swift
import SwiftUI

struct ActiveProjectsList: View {
    @StateObject private var projectService = ProjectService.shared

    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var error: String?

    let onSelectProject: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "flame")
                    .foregroundColor(.orange)
                Text("Active")
                    .font(.headline)

                if !projects.isEmpty {
                    Text("(\(projects.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Content
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if projects.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(projects) { project in
                        ProjectRowView(project: project)
                            .onTapGesture { onSelectProject(project) }
                    }
                }
                .padding()
            }
        }
        .task {
            await loadProjects()
        }
        .onChange(of: projectService.lastUpdated) {
            Task { await loadProjects() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No active projects")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Start from inbox or activate a parked project")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func loadProjects() async {
        isLoading = true

        do {
            projects = try await projectService.getActiveProjects()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    // Review badge if any thread needs review
                    if project.hasReviewBadge {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                    }
                }

                HStack(spacing: 8) {
                    Label("\(project.threadCount) threads", systemImage: "bubble.left.and.bubble.right")
                    Text("\u{2022}")
                    Label("\(project.noteCount) notes", systemImage: "doc")
                    if let time = project.timeSinceActive {
                        Text("\u{2022}")
                        Text(time)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
}
