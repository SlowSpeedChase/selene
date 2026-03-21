import SeleneShared
// StartConversationSheet.swift
// SeleneChat
//
// Phase 7.2: Planning Tab Redesign
// Project picker when starting a new conversation

import SwiftUI

struct StartConversationSheet: View {
    let note: InboxNote
    let onStart: (Int, String?) -> Void  // projectId, new project name if creating
    let onCancel: () -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @StateObject private var projectService = ProjectService.shared

    @State private var selection: Selection = .scratchPad
    @State private var newProjectName = ""
    @State private var activeProjects: [Project] = []
    @State private var parkedProjects: [Project] = []
    @State private var scratchPad: Project?
    @State private var isLoading = true

    enum Selection: Hashable {
        case scratchPad
        case existing(Int)
        case new
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Start Conversation")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Note preview
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(note.preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            // Options
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Where should this conversation live?")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)

                    // Scratch Pad option
                    if scratchPad != nil {
                        optionRow(
                            icon: "note.text",
                            title: "Scratch Pad",
                            subtitle: "Quick thought, organize later",
                            isSelected: selection == .scratchPad
                        ) {
                            selection = .scratchPad
                        }
                    }

                    // Create new project
                    optionRow(
                        icon: "plus.circle",
                        title: "Create New Project",
                        subtitle: newProjectName.isEmpty ? "Enter name below" : newProjectName,
                        isSelected: selection == .new
                    ) {
                        selection = .new
                    }

                    if selection == .new {
                        TextField("Project name", text: $newProjectName)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal)
                    }

                    // Existing projects
                    if !activeProjects.isEmpty {
                        Text("Active Projects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        ForEach(activeProjects) { project in
                            optionRow(
                                icon: "star.fill",
                                title: project.name,
                                subtitle: "\(project.threadCount) threads",
                                isSelected: selection == .existing(project.id)
                            ) {
                                selection = .existing(project.id)
                            }
                        }
                    }

                    if !parkedProjects.isEmpty {
                        Text("Parked Projects")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top, 8)

                        ForEach(parkedProjects.prefix(5)) { project in
                            optionRow(
                                icon: "moon.zzz",
                                title: project.name,
                                subtitle: "\(project.threadCount) threads",
                                isSelected: selection == .existing(project.id)
                            ) {
                                selection = .existing(project.id)
                            }
                        }
                    }
                }
                .padding(.vertical)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Start Conversation") {
                    startConversation()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
        .task {
            await loadProjects()
        }
    }

    private func optionRow(
        icon: String,
        title: String,
        subtitle: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var canStart: Bool {
        switch selection {
        case .scratchPad, .existing:
            return true
        case .new:
            return !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeProjects = try await projectService.getActiveProjects()
            parkedProjects = try await projectService.getParkedProjects()
            scratchPad = try await projectService.getScratchPad()
        } catch {
            #if DEBUG
            print("[StartConversationSheet] Error: \(error)")
            #endif
        }
    }

    private func startConversation() {
        switch selection {
        case .scratchPad:
            if let pad = scratchPad {
                onStart(pad.id, nil)
            }
        case .existing(let projectId):
            onStart(projectId, nil)
        case .new:
            onStart(-1, newProjectName)  // -1 signals create new
        }
    }
}
