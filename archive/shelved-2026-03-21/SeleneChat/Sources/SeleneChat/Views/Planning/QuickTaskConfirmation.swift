import SeleneShared
// SeleneChat/Sources/Views/Planning/QuickTaskConfirmation.swift
import SwiftUI

struct QuickTaskConfirmation: View {
    let note: InboxNote
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var taskText: String
    @State private var isSubmitting = false

    init(note: InboxNote, onConfirm: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.note = note
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        // Initialize with note title as default task text
        _taskText = State(initialValue: note.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("📋")
                Text("Quick task")
                    .font(.headline)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Original note
            VStack(alignment: .leading, spacing: 4) {
                Text("From note:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(note.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Editable task text
            VStack(alignment: .leading, spacing: 4) {
                Text("Task to create:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Task text", text: $taskText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
            }

            Divider()

            // Actions
            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Button("Send to Things") {
                    isSubmitting = true
                    onConfirm(taskText)
                }
                .buttonStyle(.borderedProminent)
                .disabled(taskText.isEmpty || isSubmitting)
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
