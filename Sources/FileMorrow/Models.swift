import Foundation
import SwiftUI

struct ArchiveCategory: RawRepresentable, Hashable, Codable, Sendable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let university = Self(rawValue: "University")
    static let finance = Self(rawValue: "Finance & PSX")
    static let medical = Self(rawValue: "Medical")
    static let work = Self(rawValue: "Work")
    static let personal = Self(rawValue: "Personal")
    static let travel = Self(rawValue: "Travel & Immigration")
    static let legal = Self(rawValue: "Legal")
    static let design = Self(rawValue: "Design")
    static let documents = Self(rawValue: "Documents")
    static let images = Self(rawValue: "Images")
    static let videos = Self(rawValue: "Videos")
    static let music = Self(rawValue: "Music")
    static let installers = Self(rawValue: "Apps & Installers")
    static let archives = Self(rawValue: "Archives")
    static let codeData = Self(rawValue: "Code & Data")
    static let other = Self(rawValue: "Other")
    static let needsReview = Self(rawValue: "Needs Review")
}

struct CategoryDefinition: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var folderName: String
    var icon: String
    var color: String
    var description: String
    var enabled: Bool
    var extensions: [String]
    var filenameKeywords: [String]
    var contentKeywords: [String]
    var examples: [String]
    var contentAware: Bool
    var extensionConfidence: Int

    var category: ArchiveCategory { .init(rawValue: id) }

    var swiftUIColor: Color {
        switch color.lowercased() {
        case "red": .red
        case "orange": .orange
        case "yellow": .yellow
        case "green": .green
        case "mint": .mint
        case "teal": .teal
        case "cyan": .cyan
        case "blue": .blue
        case "purple": .purple
        case "pink": .pink
        case "brown": .brown
        case "gray": .gray
        default: .indigo
        }
    }
}

struct OrganizationProfile: Codable, Sendable {
    var schemaVersion: Int
    var name: String
    var categories: [CategoryDefinition]

    var enabledCategories: [CategoryDefinition] {
        categories.filter(\.enabled)
    }

    func definition(for category: ArchiveCategory) -> CategoryDefinition? {
        categories.first { $0.id == category.rawValue }
    }
}

enum ClassificationMode: String, CaseIterable, Identifiable, Sendable {
    case formatOnly = "Format only"
    case smartContent = "Smart content"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formatOnly: "By File Format"
        case .smartContent: "Smart Content"
        }
    }

    var detail: String {
        switch self {
        case .formatOnly:
            "Fast and predictable. PDFs go to Documents, audio to Music, images to Images, and spreadsheets to Spreadsheets."
        case .smartContent:
            "Uses filename metadata, extracted content, and Apple Intelligence to choose subject folders. More personalized, but the on-device model can make mistakes."
        }
    }
}

enum AgeView: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case lastWeek = "Last 7 Days"
    case ready = "Ready to Archive"
    case all = "All Downloads"
    case duplicates = "Duplicates"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: "sun.max.fill"
        case .yesterday: "clock.arrow.circlepath"
        case .lastWeek: "calendar"
        case .ready: "sparkles.rectangle.stack"
        case .all: "tray.full.fill"
        case .duplicates: "doc.on.doc.fill"
        }
    }
}

struct DuplicateGroup: Identifiable, Hashable, Sendable {
    let id: String
    let files: [URL]
    let fileSize: Int64

    var keeper: URL { files[0] }
    var extras: [URL] { Array(files.dropFirst()) }
    var wastedSize: Int64 { fileSize * Int64(extras.count) }
}

struct DuplicateScanProgress: Sendable {
    enum Stage: String, Sendable {
        case fingerprinting = "Comparing candidates"
        case verifying = "Verifying exact matches"
    }

    let stage: Stage
    let completedFiles: Int
    let totalFiles: Int
    let processedBytes: Int64
    let totalBytes: Int64
    let currentFile: String?

    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(1, Double(processedBytes) / Double(totalBytes))
    }
}

struct OrganizationProposal: Identifiable, Sendable {
    let id = UUID()
    let fileCount: Int
    let totalSize: Int64
    let categoryCounts: [(name: String, count: Int)]
    let automaticCheck: Bool
}

struct FileRecord: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let dateAdded: Date
    let size: Int64
    let contentType: String
    var category: ArchiveCategory
    var confidence: Int
    var reason: String
    var source: DecisionSource
    var excerpt: String?
    let location: FileLocation

    var name: String { url.lastPathComponent }
    var isReviewed: Bool { source == .user }
    var isOrganized: Bool { location == .organized }
}

enum FileLocation: String, Hashable, Sendable {
    case loose
    case organized
}

enum DecisionSource: String, Codable, Sendable {
    case rule = "Rule"
    case localContent = "Local content"
    case appleAI = "Apple Intelligence"
    case formatFallback = "Format fallback"
    case user = "Your correction"
}

struct SavedDecision: Codable, Sendable {
    let path: String
    let modifiedAt: Date
    let category: ArchiveCategory
    let confidence: Int
    let reason: String
    let source: DecisionSource
    let modelVersion: Int?
}

struct MoveOperation: Codable, Sendable {
    let originalPath: String
    let destinationPath: String
}

struct MoveBatch: Codable, Sendable {
    let id: UUID
    let createdAt: Date
    let operations: [MoveOperation]
}

struct RuleDecision: Sendable {
    let category: ArchiveCategory
    let confidence: Int
    let reason: String
}

enum ArchiveEligibility {
    static func isEligible(_ record: FileRecord, cutoffDate: Date) -> Bool {
        !record.isOrganized && record.dateAdded < cutoffDate
    }
}
