import SwiftUI
import SeleneShared

struct MobileBriefingView: View {
    let dataProvider: DataProvider
    @State private var recentNotes: [Note] = []
    @State private var activeThreads: [SeleneShared.Thread] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                if isLoading {
                    ProgressView("Loading briefing...")
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 16) {
                        // Today's summary header
                        briefingHeader

                        // Active threads overview
                        if !activeThreads.isEmpty {
                            threadsSummaryCard
                        }

                        // Recent notes
                        if !recentNotes.isEmpty {
                            recentNotesCard
                        }

                        if activeThreads.isEmpty && recentNotes.isEmpty {
                            ContentUnavailableView(
                                "No Briefing Data",
                                systemImage: "sun.max",
                                description: Text("Capture some notes to see your morning briefing.")
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Briefing")
            .refreshable { await loadBriefing() }
            .task { await loadBriefing() }
        }
    }

    private var briefingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Good \(timeOfDayGreeting)")
                .font(.title2)
                .fontWeight(.semibold)
            Text(Date(), style: .date)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var threadsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Active Threads", systemImage: "circle.hexagongrid")
                .font(.headline)

            ForEach(activeThreads.prefix(5)) { thread in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("\(thread.noteCount) notes \u{2022} \(thread.momentumDisplay) momentum")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(thread.statusEmoji)
                }
            }
        }
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var recentNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent Notes", systemImage: "note.text")
                .font(.headline)

            ForEach(recentNotes.prefix(5)) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let event = note.calendarEvent {
                        HStack(spacing: 2) {
                            Image(systemName: "calendar")
                            Text(event.title)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(4)
                    }
                    HStack {
                        Text(note.formattedDate)
                        if let theme = note.primaryTheme {
                            Text("\u{2022}")
                            Text(theme)
                        }
                        if note.energyLevel != nil {
                            Text("\u{2022}")
                            Text(note.energyEmoji)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color.gray.opacity(0.1)
        #endif
    }

    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }

    private func loadBriefing() async {
        isLoading = recentNotes.isEmpty && activeThreads.isEmpty
        do {
            async let notesTask = dataProvider.getRecentNotes(days: 3, limit: 10)
            async let threadsTask = dataProvider.getActiveThreads(limit: 10)
            recentNotes = try await notesTask
            activeThreads = try await threadsTask
        } catch {
            // Graceful degradation
        }
        isLoading = false
    }
}
