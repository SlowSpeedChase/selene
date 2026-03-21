import SeleneShared
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var databaseService: DatabaseService
    @StateObject private var searchService = SearchService()
    @State private var searchText = ""
    @State private var selectedConcepts: Set<String> = []
    @State private var selectedThemes: Set<String> = []
    @State private var selectedEnergy: Set<String> = []
    @State private var allConcepts: [String] = []
    @State private var allThemes: [String] = []
    @State private var selectedNote: Note?
    @State private var showingFilters = false

    let energyLevels = ["high", "medium", "low"]

    var body: some View {
        HSplitView {
            // Search and filters sidebar
            VStack(spacing: 0) {
                searchHeader
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        filterSection
                    }
                    .padding()
                }
            }
            .frame(minWidth: 250, idealWidth: 300)

            // Results list
            VStack(spacing: 0) {
                resultsHeader
                Divider()

                if searchService.isSearching {
                    ProgressView("Searching...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = searchService.error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchService.results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .frame(minWidth: 300)

            // Note detail
            if let note = selectedNote {
                NoteDetailView(note: note)
                    .frame(minWidth: 400)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a note to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .task {
            await loadFilters()
            await performSearch()
        }
    }

    private var searchHeader: some View {
        VStack(spacing: 12) {
            TextField("Search notes...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await performSearch() }
                }

            HStack {
                Button(action: { Task { await performSearch() } }) {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)

                Button(action: clearFilters) {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Energy filter
            VStack(alignment: .leading, spacing: 8) {
                Label("Energy Level", systemImage: "bolt.fill")
                    .font(.headline)

                ForEach(energyLevels, id: \.self) { energy in
                    Toggle(isOn: Binding(
                        get: { selectedEnergy.contains(energy) },
                        set: { isSelected in
                            if isSelected {
                                selectedEnergy.insert(energy)
                            } else {
                                selectedEnergy.remove(energy)
                            }
                            Task { await performSearch() }
                        }
                    )) {
                        HStack {
                            Text(energy.capitalized)
                            Text(energyEmoji(for: energy))
                        }
                    }
                }
            }

            Divider()

            // Concepts filter
            VStack(alignment: .leading, spacing: 8) {
                Label("Concepts", systemImage: "lightbulb.fill")
                    .font(.headline)

                if allConcepts.isEmpty {
                    Text("No concepts found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        FlowLayout(spacing: 8) {
                            ForEach(allConcepts.prefix(20), id: \.self) { concept in
                                ConceptChip(
                                    concept: concept,
                                    isSelected: selectedConcepts.contains(concept),
                                    action: {
                                        if selectedConcepts.contains(concept) {
                                            selectedConcepts.remove(concept)
                                        } else {
                                            selectedConcepts.insert(concept)
                                        }
                                        Task { await performSearch() }
                                    }
                                )
                            }
                        }
                    }
                }
            }

            Divider()

            // Themes filter
            VStack(alignment: .leading, spacing: 8) {
                Label("Themes", systemImage: "tag.fill")
                    .font(.headline)

                if allThemes.isEmpty {
                    Text("No themes found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    FlowLayout(spacing: 8) {
                        ForEach(allThemes, id: \.self) { theme in
                            ConceptChip(
                                concept: theme,
                                isSelected: selectedThemes.contains(theme),
                                action: {
                                    if selectedThemes.contains(theme) {
                                        selectedThemes.remove(theme)
                                    } else {
                                        selectedThemes.insert(theme)
                                    }
                                    Task { await performSearch() }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    private var resultsHeader: some View {
        HStack {
            Text("\(searchService.results.count) results")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
    }

    private var resultsList: some View {
        List(searchService.results, selection: $selectedNote) { note in
            NoteRow(note: note)
                .tag(note)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No notes found")
                .font(.headline)
            Text("Try adjusting your search or filters")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func performSearch() async {
        let filters = SearchService.SearchFilters(
            query: searchText,
            concepts: Array(selectedConcepts),
            themes: Array(selectedThemes),
            energyLevels: Array(selectedEnergy)
        )

        await searchService.search(with: filters)
    }

    private func loadFilters() async {
        allConcepts = await searchService.getAllConcepts()
        allThemes = await searchService.getAllThemes()
    }

    private func clearFilters() {
        searchText = ""
        selectedConcepts.removeAll()
        selectedThemes.removeAll()
        selectedEnergy.removeAll()
        Task { await performSearch() }
    }

    private func energyEmoji(for level: String) -> String {
        switch level.lowercased() {
        case "high": return "⚡"
        case "medium": return "🔋"
        case "low": return "🪫"
        default: return ""
        }
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 4) {
                    if note.energyLevel != nil {
                        Text(note.energyEmoji)
                            .font(.caption)
                    }
                    if note.emotionalTone != nil {
                        Text(note.moodEmoji)
                            .font(.caption)
                    }
                }
            }

            Text(note.preview)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)

            HStack {
                if let theme = note.primaryTheme {
                    Text(theme)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(4)
                }

                if let event = note.calendarEvent {
                    HStack(spacing: 2) {
                        Image(systemName: "calendar")
                        Text(event.title)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
                }

                Spacer()

                Text(note.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct NoteDetailView: View {
    let note: Note
    @State private var obsidianFilePath: String?
    @State private var isLookingUpFile = true
    @State private var lookupFailed = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(note.title)
                            .font(.title2)
                            .fontWeight(.bold)

                        Spacer()

                        HStack(spacing: 8) {
                            // Open in Obsidian button
                            if isLookingUpFile {
                                ProgressView()
                                    .controlSize(.small)
                            } else if obsidianFilePath != nil {
                                Button {
                                    Task {
                                        let success = await ObsidianService.shared.openInObsidian(note: note)
                                        if !success {
                                            lookupFailed = true
                                        }
                                    }
                                } label: {
                                    Label("Open in Obsidian", systemImage: "link")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                            }

                            Text(note.energyEmoji)
                            Text(note.moodEmoji)

                            // Close button
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.title3)
                    }

                    Text(note.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // File not found message
                    if lookupFailed && !isLookingUpFile {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                            Text("Note file not found in vault")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Divider()

                // Metadata
                VStack(alignment: .leading, spacing: 12) {
                    if let theme = note.primaryTheme {
                        metadataRow(label: "Theme", value: theme)
                    }

                    if let energy = note.energyLevel {
                        metadataRow(label: "Energy", value: energy.capitalized)
                    }

                    if let mood = note.emotionalTone {
                        metadataRow(label: "Mood", value: mood.capitalized)
                    }

                    if let sentiment = note.overallSentiment {
                        metadataRow(label: "Sentiment", value: sentiment.capitalized)
                    }

                    if let event = note.calendarEvent {
                        HStack {
                            Text("Calendar")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)

                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                                Text("\(event.title) \u{00B7} \(event.formattedTimeRange)")
                                    .font(.caption)
                            }
                        }
                    }

                    if let concepts = note.concepts, !concepts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Concepts")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            FlowLayout(spacing: 8) {
                                ForEach(concepts, id: \.self) { concept in
                                    Text(concept)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.accentColor.opacity(0.2))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    Text("Content")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text(note.content)
                        .textSelection(.enabled)
                }
            }
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .task {
            // Look up file path when view appears
            if let fileURL = await ObsidianService.shared.findMarkdownFile(for: note) {
                obsidianFilePath = fileURL.path
            } else {
                lookupFailed = true
            }
            isLookingUpFile = false
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(.caption)
        }
    }
}

struct ConceptChip: View {
    let concept: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(concept)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// FlowLayout for wrapping chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                          proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
