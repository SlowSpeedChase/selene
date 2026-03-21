import SeleneShared
import Foundation

#if DEBUG

enum LogCategory: String {
    case state = "STATE"
    case error = "ERROR"
    case nav = "NAV"
    case action = "ACTION"
}

final class DebugLogger {
    static let shared = DebugLogger()

    private let logPath: String
    private let errorPath: String
    private let maxSizeBytes: Int
    private let dateFormatter: DateFormatter
    private let isoFormatter: ISO8601DateFormatter
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.selenechat.debuglogger")

    static var defaultLogPath: String {
        DatabaseService.isRunningFromAppBundle()
            ? "/tmp/selenechat-debug.log"
            : "/tmp/selenechat-dev-debug.log"
    }

    static var defaultErrorPath: String {
        DatabaseService.isRunningFromAppBundle()
            ? "/tmp/selenechat-last-error"
            : "/tmp/selenechat-dev-last-error"
    }

    init(logPath: String? = nil, maxSizeBytes: Int = 5 * 1024 * 1024, errorPath: String? = nil) {
        let logPath = logPath ?? Self.defaultLogPath
        let errorPath = errorPath ?? Self.defaultErrorPath
        self.logPath = logPath
        self.errorPath = errorPath
        self.maxSizeBytes = maxSizeBytes

        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        self.isoFormatter = ISO8601DateFormatter()

        self.fileHandle = openLogFile()
    }

    deinit {
        try? fileHandle?.close()
    }

    func log(_ category: LogCategory, _ message: String) {
        queue.async { [weak self] in
            guard let self = self else { return }

            self.rotateIfNeeded()

            let timestamp = self.dateFormatter.string(from: Date())
            let logLine = "[\(timestamp)] \(category.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0)) | \(message)\n"

            if let data = logLine.data(using: .utf8) {
                self.fileHandle?.write(data)
                try? self.fileHandle?.synchronize()
            }

            if category == .error {
                self.writeErrorAlert(message)
            }
        }
    }

    private func writeErrorAlert(_ message: String) {
        let isoTimestamp = isoFormatter.string(from: Date())
        let errorLine = "\(isoTimestamp)|\(message)"
        try? errorLine.write(toFile: errorPath, atomically: true, encoding: .utf8)
    }

    private func openLogFile() -> FileHandle? {
        // Create file if doesn't exist
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }

        let handle = FileHandle(forWritingAtPath: logPath)
        handle?.seekToEndOfFile()
        return handle
    }

    private func rotateIfNeeded() {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
              let fileSize = attributes[.size] as? Int,
              fileSize > maxSizeBytes else {
            return
        }

        // Close current handle
        try? fileHandle?.close()

        let backupPath = logPath + ".old"

        // Delete old backup if exists
        try? FileManager.default.removeItem(atPath: backupPath)

        // Move current to backup
        try? FileManager.default.moveItem(atPath: logPath, toPath: backupPath)

        // Open fresh file
        self.fileHandle = openLogFile()
    }
}

#endif
