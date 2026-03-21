import SeleneShared
import Foundation

@MainActor
class CompressionService: ObservableObject {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // Called during app idle time or on launch
    func checkAndCompressSessions() async {
        let sessions = try? await databaseService.getSessionsReadyForCompression()

        guard let sessions = sessions, !sessions.isEmpty else { return }

        for session in sessions {
            await compressSession(session)
        }
    }

    private func compressSession(_ session: ChatSession) async {
        do {
            // Mark as processing
            try await databaseService.updateCompressionState(
                sessionId: session.id,
                state: .processing
            )

            // Generate summary
            let summary = await generateSummary(for: session)

            // Compress
            try await databaseService.compressSession(
                sessionId: session.id,
                summary: summary
            )

            print("✅ Successfully compressed session: \(session.title)")
        } catch {
            print("❌ Compression failed for session \(session.id): \(error)")

            // Recovery: revert to full state
            try? await databaseService.updateCompressionState(
                sessionId: session.id,
                state: .full
            )
            print("🔄 Reverted session \(session.id) back to full state")
        }
    }

    func generateSummary(for session: ChatSession) async -> String {
        // Extract user queries from messages
        let userQueries = session.messages
            .filter { $0.role == .user }
            .map { $0.content }

        let summary = """
        Session: \(session.title)
        Date: \(session.formattedDate)
        Questions asked: \(userQueries.count)

        Key queries:
        \(userQueries.prefix(5).map { "- \($0)" }.joined(separator: "\n"))
        """

        return summary
    }
}
