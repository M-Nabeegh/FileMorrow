import Foundation

actor ProfileStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let profileURL: URL

    init() {
        let base = AppSupportPaths.directory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        profileURL = base.appending(path: "organization-profile.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func load() -> OrganizationProfile {
        let bundled = bundledProfile()
        if let data = try? Data(contentsOf: profileURL),
           let profile = try? decoder.decode(OrganizationProfile.self, from: data) {
            guard let bundled else { return profile }
            let migrated = mergeBuiltInKnowledge(into: profile, from: bundled)
            try? save(migrated)
            return migrated
        }
        if let bundled {
            try? save(bundled)
            return bundled
        }
        return Self.fallback
    }

    private func bundledProfile() -> OrganizationProfile? {
        guard let url = Bundle.main.url(forResource: "default-profile", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(OrganizationProfile.self, from: data)
    }

    /// Keeps personal names, folders, colors and enabled choices while teaching
    /// an existing profile about newly supported formats and built-in signals.
    private func mergeBuiltInKnowledge(
        into personal: OrganizationProfile,
        from bundled: OrganizationProfile
    ) -> OrganizationProfile {
        var result = personal
        result.schemaVersion = max(personal.schemaVersion, bundled.schemaVersion)

        for builtIn in bundled.categories {
            guard let index = result.categories.firstIndex(where: { $0.id == builtIn.id }) else {
                let insertion = result.categories.firstIndex { $0.category == .needsReview }
                    ?? result.categories.endIndex
                result.categories.insert(builtIn, at: insertion)
                continue
            }
            result.categories[index].extensions = merged(
                result.categories[index].extensions,
                builtIn.extensions
            )
            result.categories[index].filenameKeywords = merged(
                result.categories[index].filenameKeywords,
                builtIn.filenameKeywords
            )
            result.categories[index].contentKeywords = merged(
                result.categories[index].contentKeywords,
                builtIn.contentKeywords
            )
            result.categories[index].examples = merged(
                result.categories[index].examples,
                builtIn.examples
            )
        }
        return result
    }

    private func merged(_ personal: [String], _ builtIn: [String]) -> [String] {
        personal + builtIn.filter { candidate in
            !personal.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
    }

    func save(_ profile: OrganizationProfile) throws {
        try encoder.encode(profile).write(to: profileURL, options: .atomic)
    }

    func export(_ profile: OrganizationProfile, to url: URL) throws {
        try encoder.encode(profile).write(to: url, options: .atomic)
    }

    func importProfile(from url: URL) throws -> OrganizationProfile {
        let data = try Data(contentsOf: url)
        let profile = try decoder.decode(OrganizationProfile.self, from: data)
        guard !profile.categories.isEmpty,
              profile.categories.contains(where: { $0.id == ArchiveCategory.needsReview.rawValue }) else {
            throw ProfileError.invalidProfile
        }
        try save(profile)
        return profile
    }

    static let fallback = OrganizationProfile(
        schemaVersion: 2,
        name: "Minimal",
        categories: [
            .init(
                id: ArchiveCategory.documents.rawValue,
                name: "Documents",
                folderName: "Documents",
                icon: "doc.fill",
                color: "gray",
                description: "General documents",
                enabled: true,
                extensions: ["pdf", "doc", "docx", "ppt", "pptx", "key", "txt"],
                filenameKeywords: [],
                contentKeywords: [],
                examples: [],
                contentAware: true,
                extensionConfidence: 60
            ),
            .init(
                id: ArchiveCategory.other.rawValue,
                name: "Other",
                folderName: "Other",
                icon: "square.grid.2x2.fill",
                color: "gray",
                description: "Unsupported or extensionless files",
                enabled: true,
                extensions: [],
                filenameKeywords: [],
                contentKeywords: [],
                examples: [],
                contentAware: false,
                extensionConfidence: 100
            ),
            .init(
                id: ArchiveCategory.needsReview.rawValue,
                name: "Needs Review",
                folderName: "Needs Review",
                icon: "questionmark.folder.fill",
                color: "gray",
                description: "Ambiguous files",
                enabled: true,
                extensions: [],
                filenameKeywords: [],
                contentKeywords: [],
                examples: [],
                contentAware: true,
                extensionConfidence: 0
            )
        ]
    )
}

enum ProfileError: LocalizedError {
    case invalidProfile

    var errorDescription: String? {
        "The selected file is not a valid FileMorrow profile."
    }
}
