import SeleneShared
// SeleneChat/Sources/Views/Planning/InboxView.swift
import SwiftUI

struct InboxView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @StateObject private var inboxService = InboxService.shared
    @StateObject private var projectService = ProjectService.shared

    @State private var notes: [InboxNote] = []
    @State private var isLoading = true
    @State private var error: String?

    @State private var selectedNoteForTask: InboxNote?
    @State private var showTaskConfirmation = false

    private let thingsService = ThingsURLService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack {
                Image(systemName: "tray.and.arrow.down")
                Text("Inbox")
                    .font(.headline)

                if !notes.isEmpty {
                    Text("(\(notes.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { Task { await loadNotes() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
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
            } else if notes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(notes) { note in
                            TriageCardView(
                                note: note,
                                onCreateTask: { startTaskCreation(for: note) },
                                onAddToProject: { addToProject(note) },
                                onStartProject: { startProject(from: note) },
                                onPark: { parkNote(note) },
                                onArchive: { archiveNote(note) }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .task {
            await loadNotes()
        }
        .sheet(isPresented: $showTaskConfirmation) {
            if let note = selectedNoteForTask {
                QuickTaskConfirmation(
                    note: note,
                    onConfirm: { taskText in
                        Task { await createTask(taskText, from: note) }
                    },
                    onCancel: { showTaskConfirmation = false }
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("Inbox clear!")
                .font(.headline)
            Text("New notes will appear here for triage")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func loadNotes() async {
        isLoading = true
        error = nil

        do {
            notes = try await inboxService.getPendingNotes()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    private func startTaskCreation(for note: InboxNote) {
        selectedNoteForTask = note
        showTaskConfirmation = true
    }

    private func createTask(_ taskText: String, from note: InboxNote) async {
        do {
            try await thingsService.createTask(
                title: taskText,
                notes: nil,
                tags: [],
                energy: note.energyLevel,
                sourceNoteId: note.id,
                threadId: nil
            )
            try await inboxService.markTriaged(noteId: note.id)
            await loadNotes()
        } catch {
            self.error = error.localizedDescription
        }

        showTaskConfirmation = false
        selectedNoteForTask = nil
    }

    private func addToProject(_ note: InboxNote) {
        // TODO: Show project picker
        // For now, if suggested project exists, use that
        if let projectId = note.suggestedProjectId {
            Task {
                try? await inboxService.attachToProject(noteId: note.id, projectId: projectId)
                await loadNotes()
            }
        }
    }

    private func startProject(from note: InboxNote) {
        Task {
            do {
                print("[InboxView] Starting project from note: \(note.title)")
                let project = try await projectService.createProject(
                    name: note.title,
                    fromNoteId: note.id,
                    concept: note.concepts?.first
                )
                print("[InboxView] Created project: \(project.name) (id: \(project.id))")
                try await inboxService.markTriaged(noteId: note.id)
                print("[InboxView] Marked note as triaged")
                await loadNotes()
            } catch {
                print("[InboxView] Error creating project: \(error)")
                self.error = error.localizedDescription
            }
        }
    }

    private func parkNote(_ note: InboxNote) {
        Task {
            try? await inboxService.markTriaged(noteId: note.id)
            await loadNotes()
        }
    }

    private func archiveNote(_ note: InboxNote) {
        Task {
            try? await inboxService.markArchived(noteId: note.id)
            await loadNotes()
        }
    }
}
