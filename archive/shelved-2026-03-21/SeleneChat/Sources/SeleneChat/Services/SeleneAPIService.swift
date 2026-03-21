import SeleneShared
import Foundation

// MARK: - Error Types

enum APIError: Error, LocalizedError {
    case serverUnavailable
    case invalidResponse
    case decodingFailed(String)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .serverUnavailable:
            return "Selene backend is not running at localhost:5678"
        case .invalidResponse:
            return "Invalid response from Selene backend"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .requestFailed(let statusCode, let message):
            return "Request failed (status \(statusCode)): \(message)"
        }
    }
}

// MARK: - Request/Response Models

struct SearchRequest: Codable {
    let query: String
    let limit: Int
    let noteType: String?
    let actionability: String?

    enum CodingKeys: String, CodingKey {
        case query
        case limit
        case noteType = "note_type"
        case actionability
    }
}

struct SearchResponse: Codable {
    let query: String
    let count: Int
    let results: [SearchResult]
}

struct SearchResult: Codable {
    let id: Int
    let title: String
    let primaryTheme: String?
    let noteType: String?
    let distance: Double

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case primaryTheme = "primary_theme"
        case noteType = "note_type"
        case distance
    }
}

struct RelatedNotesRequest: Codable {
    let noteId: Int
    let limit: Int
    let includeLive: Bool

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case limit
        case includeLive = "include_live"
    }
}

struct RelatedNotesResponse: Codable {
    let noteId: Int
    let count: Int
    let results: [RelatedNoteResult]

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case count
        case results
    }
}

struct RelatedNoteResult: Codable {
    let id: Int
    let title: String
    let relationshipType: String
    let strength: Double?
    let source: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case relationshipType = "relationship_type"
        case strength
        case source
    }
}

// MARK: - SeleneAPIService

actor SeleneAPIService {
    static let shared = SeleneAPIService()

    private let baseURL = "http://localhost:5678"
    private let session: URLSession

    private var lastAvailabilityCheck: Date?
    private var cachedAvailability: Bool = false
    private let cacheTimeout: TimeInterval = 60  // Cache for 60 seconds

    private init() {
        // Configure session with 2 second timeout for health checks
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - Health Check

    /// Check if Selene backend is running and available (cached for 60s)
    func isAvailable() async -> Bool {
        // Return cached result if fresh
        if let lastCheck = lastAvailabilityCheck,
           Date().timeIntervalSince(lastCheck) < cacheTimeout {
            return cachedAvailability
        }

        // Perform actual health check with 2 second timeout
        guard let url = URL(string: "\(baseURL)/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                #if DEBUG
                DebugLogger.shared.log(.state, "SeleneAPIService.isAvailable: false (status \(statusCode))")
                #endif
                cachedAvailability = false
                lastAvailabilityCheck = Date()
                return false
            }

            // Try to decode response to verify it's valid JSON
            _ = try JSONSerialization.jsonObject(with: data)

            cachedAvailability = true
            lastAvailabilityCheck = Date()
            return true

        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "SeleneAPIService.isAvailable|health check failed: \(error.localizedDescription)")
            #endif
            cachedAvailability = false
            lastAvailabilityCheck = Date()
            return false
        }
    }

    // MARK: - API Methods

    /// Search notes using vector similarity search
    /// - Parameters:
    ///   - query: The search query
    ///   - limit: Maximum number of results (default: 10)
    ///   - noteType: Optional filter for note type
    ///   - actionability: Optional filter for actionability
    /// - Returns: Array of search results
    func searchNotes(
        query: String,
        limit: Int = 10,
        noteType: String? = nil,
        actionability: String? = nil
    ) async throws -> [SearchResult] {
        // Check availability first
        guard await isAvailable() else {
            throw APIError.serverUnavailable
        }

        guard let url = URL(string: "\(baseURL)/api/search") else {
            throw APIError.invalidResponse
        }

        // Build request body
        let requestBody = SearchRequest(
            query: query,
            limit: limit,
            noteType: noteType,
            actionability: actionability
        )

        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                #if DEBUG
                DebugLogger.shared.log(.error, "SeleneAPIService.searchNotes|status \(httpResponse.statusCode)")
                #endif
                throw APIError.serverUnavailable
            }

            // Decode response
            let searchResponse: SearchResponse
            do {
                searchResponse = try JSONDecoder().decode(SearchResponse.self, from: data)
            } catch {
                #if DEBUG
                DebugLogger.shared.log(.error, "SeleneAPIService.searchNotes|decoding failed: \(error.localizedDescription)")
                #endif
                throw APIError.decodingFailed(error.localizedDescription)
            }

            #if DEBUG
            DebugLogger.shared.log(.state, "SeleneAPIService.searchNotes: success, count=\(searchResponse.count)")
            #endif

            return searchResponse.results

        } catch let error as APIError {
            throw error
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "SeleneAPIService.searchNotes|request failed: \(error.localizedDescription)")
            #endif
            throw APIError.requestFailed(-1, error.localizedDescription)
        }
    }

    /// Get related notes for a given note ID
    /// - Parameters:
    ///   - noteId: The note ID to find related notes for
    ///   - limit: Maximum number of results (default: 5)
    ///   - includeLive: Include live associations (default: true)
    /// - Returns: Array of related note results
    func getRelatedNotes(
        noteId: Int,
        limit: Int = 5,
        includeLive: Bool = true
    ) async throws -> [RelatedNoteResult] {
        // Check availability first
        guard await isAvailable() else {
            throw APIError.serverUnavailable
        }

        guard let url = URL(string: "\(baseURL)/api/related-notes") else {
            throw APIError.invalidResponse
        }

        // Build request body
        let requestBody = RelatedNotesRequest(
            noteId: noteId,
            limit: limit,
            includeLive: includeLive
        )

        // Create URLRequest
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30.0

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                #if DEBUG
                DebugLogger.shared.log(.error, "SeleneAPIService.getRelatedNotes|status \(httpResponse.statusCode)")
                #endif
                throw APIError.serverUnavailable
            }

            // Decode response
            let relatedResponse: RelatedNotesResponse
            do {
                relatedResponse = try JSONDecoder().decode(RelatedNotesResponse.self, from: data)
            } catch {
                #if DEBUG
                DebugLogger.shared.log(.error, "SeleneAPIService.getRelatedNotes|decoding failed: \(error.localizedDescription)")
                #endif
                throw APIError.decodingFailed(error.localizedDescription)
            }

            #if DEBUG
            DebugLogger.shared.log(.state, "SeleneAPIService.getRelatedNotes: success, count=\(relatedResponse.count)")
            #endif

            return relatedResponse.results

        } catch let error as APIError {
            throw error
        } catch {
            #if DEBUG
            DebugLogger.shared.log(.error, "SeleneAPIService.getRelatedNotes|request failed: \(error.localizedDescription)")
            #endif
            throw APIError.requestFailed(-1, error.localizedDescription)
        }
    }
}
