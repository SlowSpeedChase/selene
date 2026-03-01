import SeleneShared
import Foundation
import AppKit

/// Service for interacting with Obsidian vault
/// Handles file lookup and opening notes in Obsidian
class ObsidianService {
    static let shared = ObsidianService()

    private let vaultPath = "/Users/chaseeasterling/selene/vault"  // Obsidian vault root
    private let seleneFolder = "Selene"  // Subfolder for Selene notes
    private let vaultName = "vault"  // Obsidian vault name

    private init() {}

    /// Find markdown file in vault for a given note
    /// Searches by date prefix and verifies title in frontmatter
    func findMarkdownFile(for note: Note) async -> URL? {
        // Format note date as YYYY-MM-DD
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC") // Match database UTC storage
        let datePrefix = dateFormatter.string(from: note.createdAt)

        print("ObsidianService: Looking for note '\(note.title)' with date prefix '\(datePrefix)'")

        // Collect matching file URLs - must be done synchronously
        // FileManager.DirectoryEnumerator is not Sendable and can't cross async boundaries
        let candidateURLs = Self.findCandidateFiles(
            in: vaultPath,
            withDatePrefix: datePrefix
        )

        // Now verify titles asynchronously
        for fileURL in candidateURLs {
            if await verifyNoteTitle(fileURL: fileURL, expectedTitle: note.title) {
                print("ObsidianService: Found matching file: \(fileURL.path)")
                return fileURL
            }
        }

        print("ObsidianService: No matching file found for note: \(note.title) (\(datePrefix))")
        return nil
    }
    
    /// Synchronous helper to find candidate files by date prefix
    /// Separated to avoid async/Sendable issues with FileManager.DirectoryEnumerator
    private static func findCandidateFiles(in vaultPath: String, withDatePrefix datePrefix: String) -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: vaultPath),
            includingPropertiesForKeys: [.nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            print("ObsidianService: Failed to create enumerator for vault path: \(vaultPath)")
            return []
        }

        var urls: [URL] = []
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            if filename.hasPrefix(datePrefix) && filename.hasSuffix(".md") {
                urls.append(fileURL)
            }
        }
        return urls
    }

    /// Generate Obsidian URI for a file path
    func generateObsidianURI(for filePath: String) -> URL? {
        // Convert absolute path to relative path within vault
        guard filePath.hasPrefix(vaultPath) else {
            print("ObsidianService: File path is not in vault: \(filePath)")
            return nil
        }

        let relativePath = filePath
            .replacingOccurrences(of: vaultPath + "/", with: "")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""

        // Format: obsidian://open?vault=<name>&file=<path>
        let uriString = "obsidian://open?vault=\(vaultName)&file=\(relativePath)"

        guard let uri = URL(string: uriString) else {
            print("ObsidianService: Failed to create URI from string: \(uriString)")
            return nil
        }

        print("ObsidianService: Generated URI: \(uriString)")
        return uri
    }

    /// Open note in Obsidian (combines findMarkdownFile + open URI)
    func openInObsidian(note: Note) async -> Bool {
        guard let fileURL = await findMarkdownFile(for: note) else {
            print("ObsidianService: Cannot open note - file not found")
            return false
        }

        guard let obsidianURI = generateObsidianURI(for: fileURL.path) else {
            print("ObsidianService: Cannot open note - failed to generate URI")
            return false
        }

        // Open URI using macOS system
        _ = await MainActor.run {
            NSWorkspace.shared.open(obsidianURI)
        }

        print("ObsidianService: Opened note in Obsidian: \(note.title)")
        return true
    }

    /// Verify note title by parsing frontmatter
    private func verifyNoteTitle(fileURL: URL, expectedTitle: String) async -> Bool {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("ObsidianService: Failed to read file: \(fileURL.path)")
            return false
        }

        // Parse YAML frontmatter
        // Look for: title: "Expected Title"
        let lines = content.components(separatedBy: .newlines)
        var inFrontmatter = false

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine == "---" {
                inFrontmatter.toggle()

                // If we've exited frontmatter without finding title, stop searching
                if !inFrontmatter {
                    break
                }
                continue
            }

            if inFrontmatter && line.hasPrefix("title:") {
                let titleValue = line
                    .replacingOccurrences(of: "title:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

                // Normalize both titles for comparison (case-insensitive, ignore quote style differences)
                // Use Unicode escapes: \u{2018}=' \u{2019}=' \u{201C}=" \u{201D}="
                let normalizedExpected = expectedTitle.lowercased()
                    .replacingOccurrences(of: "\u{2018}", with: "'")
                    .replacingOccurrences(of: "\u{2019}", with: "'")
                    .replacingOccurrences(of: "\u{201C}", with: "\"")
                    .replacingOccurrences(of: "\u{201D}", with: "\"")
                let normalizedActual = titleValue.lowercased()
                    .replacingOccurrences(of: "\u{2018}", with: "'")
                    .replacingOccurrences(of: "\u{2019}", with: "'")
                    .replacingOccurrences(of: "\u{201C}", with: "\"")
                    .replacingOccurrences(of: "\u{201D}", with: "\"")

                let matches = normalizedExpected == normalizedActual

                if matches {
                    print("ObsidianService: Title verified: \(expectedTitle)")
                } else {
                    print("ObsidianService: Title mismatch - expected: '\(expectedTitle)', got: '\(titleValue)'")
                }

                return matches
            }
        }

        print("ObsidianService: No title found in frontmatter for: \(fileURL.path)")
        return false
    }
}
