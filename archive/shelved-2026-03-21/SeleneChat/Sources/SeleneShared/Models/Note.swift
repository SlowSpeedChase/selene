import Foundation

public struct CalendarEventContext: Codable, Hashable {
    public let title: String
    public let startDate: String
    public let endDate: String
    public let calendar: String
    public let isAllDay: Bool

    public init(title: String, startDate: String, endDate: String, calendar: String, isAllDay: Bool) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.calendar = calendar
        self.isAllDay = isAllDay
    }

    /// Formatted time range like "5:00 PM–7:00 PM"
    public var formattedTimeRange: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        guard let start = isoFormatter.date(from: startDate),
              let end = isoFormatter.date(from: endDate) else {
            return ""
        }

        return "\(timeFormatter.string(from: start))\u{2013}\(timeFormatter.string(from: end))"
    }
}

public struct Note: Identifiable, Codable, Hashable {
    public let id: Int
    public let title: String
    public let content: String
    public let contentHash: String
    public let sourceType: String
    public let wordCount: Int
    public let characterCount: Int
    public let tags: [String]?
    public let createdAt: Date
    public let importedAt: Date
    public let processedAt: Date?
    public let exportedAt: Date?
    public let status: String
    public let exportedToObsidian: Bool
    public let sourceUUID: String?
    public let testRun: String?

    // Processed note data (from join)
    public var concepts: [String]?
    public var conceptConfidence: [String: Double]?
    public var primaryTheme: String?
    public var secondaryThemes: [String]?
    public var themeConfidence: Double?
    public var overallSentiment: String?
    public var sentimentScore: Double?
    public var emotionalTone: String?
    public var energyLevel: String?
    public var essence: String?
    public var fidelityTier: String?
    public var calendarEvent: CalendarEventContext?

    enum CodingKeys: String, CodingKey {
        case id, title, content
        case contentHash = "content_hash"
        case sourceType = "source_type"
        case wordCount = "word_count"
        case characterCount = "character_count"
        case tags
        case createdAt = "created_at"
        case importedAt = "imported_at"
        case processedAt = "processed_at"
        case exportedAt = "exported_at"
        case status
        case exportedToObsidian = "exported_to_obsidian"
        case sourceUUID = "source_uuid"
        case testRun = "test_run"
        case concepts
        case conceptConfidence = "concept_confidence"
        case primaryTheme = "primary_theme"
        case secondaryThemes = "secondary_themes"
        case themeConfidence = "theme_confidence"
        case overallSentiment = "overall_sentiment"
        case sentimentScore = "sentiment_score"
        case emotionalTone = "emotional_tone"
        case energyLevel = "energy_level"
        case essence
        case fidelityTier = "fidelity_tier"
        case calendarEvent = "calendar_event"
    }

    public init(
        id: Int,
        title: String,
        content: String,
        contentHash: String,
        sourceType: String,
        wordCount: Int,
        characterCount: Int,
        tags: [String]? = nil,
        createdAt: Date,
        importedAt: Date,
        processedAt: Date? = nil,
        exportedAt: Date? = nil,
        status: String,
        exportedToObsidian: Bool,
        sourceUUID: String? = nil,
        testRun: String? = nil,
        concepts: [String]? = nil,
        conceptConfidence: [String: Double]? = nil,
        primaryTheme: String? = nil,
        secondaryThemes: [String]? = nil,
        themeConfidence: Double? = nil,
        overallSentiment: String? = nil,
        sentimentScore: Double? = nil,
        emotionalTone: String? = nil,
        energyLevel: String? = nil,
        essence: String? = nil,
        fidelityTier: String? = nil,
        calendarEvent: CalendarEventContext? = nil
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.contentHash = contentHash
        self.sourceType = sourceType
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.tags = tags
        self.createdAt = createdAt
        self.importedAt = importedAt
        self.processedAt = processedAt
        self.exportedAt = exportedAt
        self.status = status
        self.exportedToObsidian = exportedToObsidian
        self.sourceUUID = sourceUUID
        self.testRun = testRun
        self.concepts = concepts
        self.conceptConfidence = conceptConfidence
        self.primaryTheme = primaryTheme
        self.secondaryThemes = secondaryThemes
        self.themeConfidence = themeConfidence
        self.overallSentiment = overallSentiment
        self.sentimentScore = sentimentScore
        self.emotionalTone = emotionalTone
        self.energyLevel = energyLevel
        self.essence = essence
        self.fidelityTier = fidelityTier
        self.calendarEvent = calendarEvent
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        sourceType = try container.decode(String.self, forKey: .sourceType)
        wordCount = try container.decode(Int.self, forKey: .wordCount)
        characterCount = try container.decode(Int.self, forKey: .characterCount)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        importedAt = try container.decode(Date.self, forKey: .importedAt)
        processedAt = try container.decodeIfPresent(Date.self, forKey: .processedAt)
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt)
        status = try container.decode(String.self, forKey: .status)
        exportedToObsidian = try container.decode(Bool.self, forKey: .exportedToObsidian)
        sourceUUID = try container.decodeIfPresent(String.self, forKey: .sourceUUID)
        testRun = try container.decodeIfPresent(String.self, forKey: .testRun)
        concepts = try container.decodeIfPresent([String].self, forKey: .concepts)
        conceptConfidence = try container.decodeIfPresent([String: Double].self, forKey: .conceptConfidence)
        primaryTheme = try container.decodeIfPresent(String.self, forKey: .primaryTheme)
        secondaryThemes = try container.decodeIfPresent([String].self, forKey: .secondaryThemes)
        themeConfidence = try container.decodeIfPresent(Double.self, forKey: .themeConfidence)
        overallSentiment = try container.decodeIfPresent(String.self, forKey: .overallSentiment)
        sentimentScore = try container.decodeIfPresent(Double.self, forKey: .sentimentScore)
        emotionalTone = try container.decodeIfPresent(String.self, forKey: .emotionalTone)
        energyLevel = try container.decodeIfPresent(String.self, forKey: .energyLevel)
        essence = try container.decodeIfPresent(String.self, forKey: .essence)
        fidelityTier = try container.decodeIfPresent(String.self, forKey: .fidelityTier)

        // calendar_event is stored as a JSON string in SQLite
        if let jsonString = try container.decodeIfPresent(String.self, forKey: .calendarEvent),
           let data = jsonString.data(using: .utf8) {
            calendarEvent = try? JSONDecoder().decode(CalendarEventContext.self, from: data)
        } else {
            calendarEvent = try container.decodeIfPresent(CalendarEventContext.self, forKey: .calendarEvent)
        }
    }

    public var energyEmoji: String {
        switch energyLevel?.lowercased() {
        case "high": return "\u{26A1}"
        case "medium": return "\u{1F50B}"
        case "low": return "\u{1FAAB}"
        default: return "\u{1F50B}"
        }
    }

    public var sentimentEmoji: String {
        switch overallSentiment?.lowercased() {
        case "positive": return "\u{1F60A}"
        case "negative": return "\u{1F614}"
        case "neutral": return "\u{1F610}"
        default: return "\u{1F610}"
        }
    }

    public var moodEmoji: String {
        switch emotionalTone?.lowercased() {
        case "excited": return "\u{1F680}"
        case "calm": return "\u{1F60C}"
        case "anxious": return "\u{1F630}"
        case "frustrated": return "\u{1F624}"
        case "happy": return "\u{1F60A}"
        case "sad": return "\u{1F622}"
        default: return "\u{1F610}"
        }
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    public var preview: String {
        String(content.prefix(200))
    }
}

#if DEBUG
extension Note {
    public static func mock(
        id: Int = 1,
        title: String = "Test Note",
        content: String = "Test content",
        contentHash: String = "mock-hash",
        sourceType: String = "test",
        wordCount: Int = 2,
        characterCount: Int = 12,
        tags: [String]? = nil,
        createdAt: Date = Date(),
        importedAt: Date = Date(),
        processedAt: Date? = nil,
        exportedAt: Date? = nil,
        status: String = "processed",
        exportedToObsidian: Bool = false,
        sourceUUID: String? = nil,
        testRun: String? = nil,
        concepts: [String]? = nil,
        conceptConfidence: [String: Double]? = nil,
        primaryTheme: String? = nil,
        secondaryThemes: [String]? = nil,
        themeConfidence: Double? = nil,
        overallSentiment: String? = nil,
        sentimentScore: Double? = nil,
        emotionalTone: String? = nil,
        energyLevel: String? = nil,
        essence: String? = nil,
        fidelityTier: String? = nil,
        calendarEvent: CalendarEventContext? = nil
    ) -> Note {
        Note(
            id: id,
            title: title,
            content: content,
            contentHash: contentHash,
            sourceType: sourceType,
            wordCount: wordCount,
            characterCount: characterCount,
            tags: tags,
            createdAt: createdAt,
            importedAt: importedAt,
            processedAt: processedAt,
            exportedAt: exportedAt,
            status: status,
            exportedToObsidian: exportedToObsidian,
            sourceUUID: sourceUUID,
            testRun: testRun,
            concepts: concepts,
            conceptConfidence: conceptConfidence,
            primaryTheme: primaryTheme,
            secondaryThemes: secondaryThemes,
            themeConfidence: themeConfidence,
            overallSentiment: overallSentiment,
            sentimentScore: sentimentScore,
            emotionalTone: emotionalTone,
            energyLevel: energyLevel,
            essence: essence,
            fidelityTier: fidelityTier,
            calendarEvent: calendarEvent
        )
    }
}
#endif
