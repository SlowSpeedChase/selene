// SeleneChat/Sources/SeleneShared/Models/AIProvider.swift
import Foundation

public enum AIProvider: String, Codable, CaseIterable {
    case local   // Ollama
    case cloud   // Claude API

    public var displayName: String {
        switch self {
        case .local: return "Local"
        case .cloud: return "Cloud"
        }
    }

    public var icon: String {
        switch self {
        case .local: return "\u{1F3E0}"
        case .cloud: return "\u{2601}\u{FE0F}"
        }
    }

    public var systemImage: String {
        switch self {
        case .local: return "house.fill"
        case .cloud: return "cloud.fill"
        }
    }
}
