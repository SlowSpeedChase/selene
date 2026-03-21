import SeleneShared
import Foundation
import SwiftUI
import SQLite

@MainActor
class TodayViewModel: ObservableObject {
    @Published var newCaptures: [NoteWithThread] = []
    @Published var heatingUpThreads: [ThreadSummary] = []
    @Published var isLoading = false
    @Published var error: String?

    private var todayService: TodayService?
    private var lastRefresh: Date?

    private let lastOpenKey = "lastAppOpen"

    func configure(with db: Connection) {
        self.todayService = TodayService(db: db)
    }

    /// Calculate cutoff: min(24h ago, last app open) - returns the EARLIER date to capture more
    func getNewCutoff() -> Date {
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let lastOpen = UserDefaults.standard.object(forKey: lastOpenKey) as? Date ?? Date.distantPast
        return min(twentyFourHoursAgo, lastOpen)
    }

    /// Record current time as last app open
    func recordAppOpen() {
        UserDefaults.standard.set(Date(), forKey: lastOpenKey)
    }

    /// Refresh data from database
    func refresh() async {
        guard let service = todayService else {
            error = "Service not configured"
            return
        }

        isLoading = true
        error = nil

        do {
            let cutoff = getNewCutoff()
            newCaptures = try service.getNewCaptures(since: cutoff)
            heatingUpThreads = try service.getHeatingUpThreads()
            lastRefresh = Date()
        } catch {
            self.error = "Failed to load: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Check if refresh needed (>5 min since last)
    func shouldRefresh() -> Bool {
        guard let last = lastRefresh else { return true }
        return Date().timeIntervalSince(last) > 300
    }

    /// Whether both columns are empty
    var isEmpty: Bool {
        newCaptures.isEmpty && heatingUpThreads.isEmpty
    }
}
