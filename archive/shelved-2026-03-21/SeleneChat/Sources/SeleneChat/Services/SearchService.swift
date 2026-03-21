import SeleneShared
import Foundation

class SearchService: ObservableObject {
    private let databaseService: DatabaseService

    @Published var results: [Note] = []
    @Published var isSearching = false
    @Published var error: String?

    init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }

    struct SearchFilters {
        var query: String = ""
        var concepts: [String] = []
        var themes: [String] = []
        var energyLevels: [String] = []
        var sentiments: [String] = []
        var dateFrom: Date?
        var dateTo: Date?

        var isEmpty: Bool {
            query.isEmpty &&
            concepts.isEmpty &&
            themes.isEmpty &&
            energyLevels.isEmpty &&
            sentiments.isEmpty &&
            dateFrom == nil &&
            dateTo == nil
        }
    }

    func search(with filters: SearchFilters) async {
        await MainActor.run { isSearching = true }
        defer { Task { await MainActor.run { isSearching = false } } }

        do {
            var notes: [Note] = []

            // If only text query
            if !filters.query.isEmpty && filters.concepts.isEmpty && filters.themes.isEmpty {
                notes = try await databaseService.searchNotes(query: filters.query)
            }
            // If concept filter
            else if !filters.concepts.isEmpty {
                for concept in filters.concepts {
                    let conceptNotes = try await databaseService.getNoteByConcept(concept)
                    notes.append(contentsOf: conceptNotes)
                }
            }
            // If theme filter
            else if !filters.themes.isEmpty {
                for theme in filters.themes {
                    let themeNotes = try await databaseService.getNotesByTheme(theme)
                    notes.append(contentsOf: themeNotes)
                }
            }
            // If energy filter
            else if !filters.energyLevels.isEmpty {
                for energy in filters.energyLevels {
                    let energyNotes = try await databaseService.getNotesByEnergy(energy)
                    notes.append(contentsOf: energyNotes)
                }
            }
            // If date range
            else if let from = filters.dateFrom, let to = filters.dateTo {
                notes = try await databaseService.getNotesByDateRange(from: from, to: to)
            }
            // Default: get all recent notes
            else {
                notes = try await databaseService.getAllNotes(limit: 100)
            }

            // Apply additional filters
            if !filters.query.isEmpty && (!filters.concepts.isEmpty || !filters.themes.isEmpty || !filters.energyLevels.isEmpty) {
                notes = notes.filter { note in
                    note.content.localizedCaseInsensitiveContains(filters.query) ||
                    note.title.localizedCaseInsensitiveContains(filters.query)
                }
            }

            if !filters.sentiments.isEmpty {
                notes = notes.filter { note in
                    guard let sentiment = note.overallSentiment else { return false }
                    return filters.sentiments.contains(sentiment)
                }
            }

            // Remove duplicates
            let uniqueNotes = Array(Set(notes)).sorted { $0.createdAt > $1.createdAt }

            await MainActor.run {
                results = uniqueNotes
                error = nil
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                results = []
            }
        }
    }

    func getAllConcepts() async -> [String] {
        do {
            let notes = try await databaseService.getAllNotes(limit: 1000)
            var concepts = Set<String>()

            for note in notes {
                if let noteConcepts = note.concepts {
                    concepts.formUnion(noteConcepts)
                }
            }

            return Array(concepts).sorted()
        } catch {
            return []
        }
    }

    func getAllThemes() async -> [String] {
        do {
            let notes = try await databaseService.getAllNotes(limit: 1000)
            var themes = Set<String>()

            for note in notes {
                if let theme = note.primaryTheme {
                    themes.insert(theme)
                }
                if let secondary = note.secondaryThemes {
                    themes.formUnion(secondary)
                }
            }

            return Array(themes).sorted()
        } catch {
            return []
        }
    }

    func clearResults() {
        results = []
        error = nil
    }
}
