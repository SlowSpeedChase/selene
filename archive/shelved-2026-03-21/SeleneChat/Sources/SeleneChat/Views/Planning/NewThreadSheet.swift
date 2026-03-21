import SeleneShared
// NewThreadSheet.swift
// SeleneChat
//
// Phase 7.2: Planning Tab Redesign
// Simple sheet for creating a new thread directly in a project

import SwiftUI

struct NewThreadSheet: View {
    let projectId: Int
    let projectName: String
    let onCreate: (DiscussionThread) -> Void
    let onCancel: () -> Void

    @EnvironmentObject var databaseService: DatabaseService
    @State private var topic = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Thread")
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

            // Project context
            HStack {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text("In: \(projectName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.05))

            Divider()

            // Topic input
            VStack(alignment: .leading, spacing: 8) {
                Text("What do you want to discuss?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("e.g., API design for user auth", text: $topic)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createThread() }

                Text("This becomes the thread's name. You can always change it later.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            Divider()

            // Actions
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button("Create Thread") {
                    createThread()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isCreating)
            }
            .padding()
        }
        .frame(width: 400, height: 280)
    }

    private var canCreate: Bool {
        !topic.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createThread() {
        guard canCreate else { return }

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let thread = try await databaseService.createThread(
                    projectId: projectId,
                    rawNoteId: nil,  // No associated note
                    threadType: .planning,
                    prompt: topic.trimmingCharacters(in: .whitespaces),
                    threadName: topic.trimmingCharacters(in: .whitespaces)
                )
                await MainActor.run {
                    onCreate(thread)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create thread: \(error.localizedDescription)"
                    isCreating = false
                }
            }
        }
    }
}
