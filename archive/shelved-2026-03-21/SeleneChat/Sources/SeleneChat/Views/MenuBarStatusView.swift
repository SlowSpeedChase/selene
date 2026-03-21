import SeleneShared
import SwiftUI

/// Minimal status dropdown view for the menu bar popover.
///
/// Displays the current workflow scheduler status (active/idle),
/// a list of all scheduled workflows with their run state,
/// an "Open Selene" button to bring the main window to front,
/// and a "Quit" button to terminate the app.
struct MenuBarStatusView: View {
    @EnvironmentObject var scheduler: WorkflowScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusLine
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            workflowList
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            if let error = scheduler.lastError {
                Divider()
                errorLine(error)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }

            Divider()

            openSeleneButton
                .padding(.horizontal, 4)
                .padding(.top, 4)

            quitButton
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .frame(width: 240)
    }

    // MARK: - Status Line

    private var isActive: Bool {
        !scheduler.activeWorkflows.isEmpty
    }

    private var statusDotSymbol: String {
        isActive ? "circle.fill" : "circle"
    }

    private var statusDotColor: Color {
        isActive ? .green : .secondary
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: statusDotSymbol)
                .font(.system(size: 8))
                .foregroundColor(statusDotColor)

            Text(scheduler.statusText)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Workflow List

    private var workflowList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(scheduler.workflowSnapshots) { snapshot in
                workflowRow(snapshot)
            }
        }
    }

    private func workflowRow(_ snapshot: WorkflowScheduler.WorkflowSnapshot) -> some View {
        HStack(spacing: 6) {
            if snapshot.isRunning {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: snapshot.usesOllama ? "brain" : "gearshape")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(width: 12, height: 12)
            }

            Text(snapshot.name)
                .font(.caption)
                .foregroundColor(snapshot.isRunning ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            if snapshot.isRunning {
                Text("running")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else if let lastRun = snapshot.lastRunAt {
                Text(relativeTime(lastRun))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("pending")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 1)
    }

    // MARK: - Error Line

    private func errorLine(_ error: WorkflowScheduler.WorkflowError) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange)

            Text("\(error.workflowName): \(error.message)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Buttons

    private var openSeleneButton: some View {
        Button(action: openSelene) {
            HStack {
                Text("Open Selene")
                Spacer()
                Text("\u{2318}O")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .keyboardShortcut("o", modifiers: .command)
    }

    private var quitButton: some View {
        Button(action: quitApp) {
            HStack {
                Text("Quit")
                Spacer()
                Text("\u{2318}Q")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .keyboardShortcut("q", modifiers: .command)
    }

    // MARK: - Actions

    private func openSelene() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }
}

// MARK: - Preview

#if DEBUG
struct MenuBarStatusView_Previews: PreviewProvider {
    static var previews: some View {
        MenuBarStatusView()
            .environmentObject(WorkflowScheduler())
            .previewDisplayName("Idle")
    }
}
#endif
