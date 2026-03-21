import SeleneShared
// SeleneChat/Sources/Views/Planning/ParkedProjectsList.swift
import SwiftUI

struct ParkedProjectsList: View {
    @StateObject private var projectService = ProjectService.shared

    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var isExpanded = false
    @State private var error: String?

    let onSelectProject: (Project) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header (always visible)
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "parkingsign")
                        .foregroundColor(.gray)
                    Text("Parked")
                        .font(.headline)

                    if !projects.isEmpty {
                        Text("(\(projects.count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if isExpanded {
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
                    Text("No parked projects")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(projects) { project in
                            ParkedProjectRow(
                                project: project,
                                onActivate: { activateProject(project) },
                                onSelect: { onSelectProject(project) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadProjects()
        }
        .onChange(of: projectService.lastUpdated) {
            Task { await loadProjects() }
        }
    }

    private func loadProjects() async {
        isLoading = true

        do {
            projects = try await projectService.getParkedProjects()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func activateProject(_ project: Project) {
        Task {
            do {
                try await projectService.activateProject(project.id)
                await loadProjects()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct ParkedProjectRow: View {
    let project: Project
    let onActivate: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.caption)

                if let time = project.timeSinceActive {
                    Text("Last active \(time)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .onTapGesture { onSelect() }

            Spacer()

            Button("Activate") {
                onActivate()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}
