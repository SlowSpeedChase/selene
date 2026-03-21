import SeleneShared
import Foundation

#if DEBUG

final class DebugSnapshotService {
    static let shared = DebugSnapshotService()

    private let requestPath: String
    private let outputPath: String
    private var providers: [String: DebugSnapshotProvider] = [:]
    private var timer: Timer?
    private let dateFormatter: ISO8601DateFormatter

    static var defaultRequestPath: String {
        DatabaseService.isRunningFromAppBundle()
            ? "/tmp/selenechat-snapshot-request"
            : "/tmp/selenechat-dev-snapshot-request"
    }

    static var defaultOutputPath: String {
        DatabaseService.isRunningFromAppBundle()
            ? "/tmp/selenechat-snapshot.json"
            : "/tmp/selenechat-dev-snapshot.json"
    }

    init(
        requestPath: String? = nil,
        outputPath: String? = nil
    ) {
        let requestPath = requestPath ?? Self.defaultRequestPath
        let outputPath = outputPath ?? Self.defaultOutputPath
        self.requestPath = requestPath
        self.outputPath = outputPath
        self.dateFormatter = ISO8601DateFormatter()
    }

    deinit {
        stopWatching()
    }

    func registerProvider(named name: String, provider: DebugSnapshotProvider) {
        providers[name] = provider
    }

    func startWatching(interval: TimeInterval = 2.0) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForRequest()
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func checkForRequest() {
        // Try to delete the request file - if it succeeds, generate snapshot
        // This avoids TOCTOU race between check and delete
        do {
            try FileManager.default.removeItem(atPath: requestPath)
            // File existed and was deleted, generate snapshot
            generateSnapshot()
        } catch {
            // File didn't exist or couldn't be deleted - that's fine, nothing to do
        }
    }

    func generateSnapshot() {
        var snapshot: [String: Any] = [
            "timestamp": dateFormatter.string(from: Date())
        ]

        // Collect from all providers
        for (name, provider) in providers {
            snapshot[name] = provider.debugSnapshot()
        }

        // Write to file
        do {
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: outputPath))
        } catch {
            DebugLogger.shared.log(.error, "Failed to write snapshot: \(error.localizedDescription)")
        }
    }
}

#endif
