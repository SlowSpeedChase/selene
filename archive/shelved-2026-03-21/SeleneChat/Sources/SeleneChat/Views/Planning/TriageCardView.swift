import SeleneShared
// SeleneChat/Sources/Views/Planning/TriageCardView.swift
import SwiftUI

struct TriageCardView: View {
    let note: InboxNote
    let onCreateTask: () -> Void
    let onAddToProject: () -> Void
    let onStartProject: () -> Void
    let onPark: () -> Void
    let onArchive: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Type badge and date
            HStack {
                typeBadge
                Spacer()
                Text(note.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Note content
            Text(note.title)
                .font(.headline)
                .lineLimit(1)

            Text(note.preview)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Suggested project (if relates_to_project)
            if let projectName = note.suggestedProjectName {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.caption)
                    Text(projectName)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }

            // Action buttons
            actionButtons
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    @ViewBuilder
    private var typeBadge: some View {
        if let type = note.suggestedType {
            HStack(spacing: 4) {
                Text(type.emoji)
                Text(type.displayName)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Primary actions based on type
            if note.suggestedType == .quickTask {
                Button("Create Task") { onCreateTask() }
                    .buttonStyle(.borderedProminent)
            } else if note.suggestedType == .relatesToProject {
                Button("Add to Project") { onAddToProject() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Start Project") { onStartProject() }
                    .buttonStyle(.borderedProminent)
            }

            Button("Park") { onPark() }
                .buttonStyle(.bordered)

            Button(action: onArchive) {
                Image(systemName: "archivebox")
            }
            .buttonStyle(.bordered)
        }
        .font(.caption)
    }
}
