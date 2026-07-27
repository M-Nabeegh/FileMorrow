import Foundation
import UniformTypeIdentifiers

actor FileScanner {
    private let ignoredNames: Set<String> = [
        ".DS_Store", ".localized", ".downloads-butler-source", "DownloadsButler",
        "Downloads Butler Archive", "FileMorrow Archive"
    ]
    private let ageURL: URL
    private let recoveryFlagURL: URL

    init() {
        let base = AppSupportPaths.directory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        ageURL = base.appending(path: "file-ages.json")
        recoveryFlagURL = base.appending(path: "recover-ages-from-modification")
    }

    func scan(
        downloadsURL: URL,
        saved: [String: SavedDecision],
        profile: OrganizationProfile,
        mode: ClassificationMode
    ) -> [FileRecord] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileSizeKey, .creationDateKey,
            .contentModificationDateKey, .addedToDirectoryDateKey, .contentTypeKey
        ]
        guard let looseURLs = try? FileManager.default.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates = looseURLs.map { ($0, FileLocation.loose) }
        for definition in profile.enabledCategories where definition.category != .needsReview {
            let folder = downloadsURL.appending(path: definition.folderName, directoryHint: .isDirectory)
            guard AppSupportPaths.hasManagedMarker(in: folder),
                  let organizedURLs = try? FileManager.default.contentsOfDirectory(
                      at: folder,
                      includingPropertiesForKeys: Array(keys),
                      options: [.skipsHiddenFiles]
                  ) else { continue }
            candidates.append(contentsOf: organizedURLs.map { ($0, FileLocation.organized) })
        }

        var stableAges = loadAges()
        let recoverFromModification = FileManager.default.fileExists(atPath: recoveryFlagURL.path)

        let records: [FileRecord] = candidates.compactMap { candidate -> FileRecord? in
            let (url, location) = candidate
            guard !ignoredNames.contains(url.lastPathComponent),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }

            let modified = values.contentModificationDate ?? .distantPast
            let systemAdded = values.addedToDirectoryDate ?? values.creationDate ?? modified
            let originalPath = downloadsURL.appending(path: url.lastPathComponent).path
            let added = stableAges[url.path]
                ?? (location == .organized ? stableAges[originalPath] : nil)
                ?? (recoverFromModification ? modified : systemAdded)
            stableAges[url.path] = added
            let rule = RuleClassifier.classify(
                url: url,
                type: values.contentType,
                profile: profile,
                mode: mode
            )
            let persisted = (saved[url.path] ?? (location == .organized ? saved[originalPath] : nil))
                .flatMap { abs($0.modifiedAt.timeIntervalSince(modified)) < 1 ? $0 : nil }
                .flatMap { decision in
                    [.appleAI, .localContent, .formatFallback].contains(decision.source)
                        && decision.modelVersion != 6
                        ? nil
                        : decision
                }
                .flatMap { decision in
                    profile.definition(for: decision.category)?.enabled == true ? decision : nil
                }
                .flatMap { decision in
                    mode == .formatOnly && decision.source != .user ? nil : decision
                }

            return FileRecord(
                url: url,
                dateAdded: added,
                size: Int64(values.fileSize ?? 0),
                contentType: values.contentType?.identifier ?? "",
                category: persisted?.category ?? rule.category,
                confidence: persisted?.confidence ?? rule.confidence,
                reason: persisted?.reason ?? rule.reason,
                source: persisted?.source ?? .rule,
                excerpt: nil,
                location: location
            )
        }
        saveAges(stableAges)
        if recoverFromModification {
            try? FileManager.default.removeItem(at: recoveryFlagURL)
        }
        return records
    }

    private func loadAges() -> [String: Date] {
        guard let data = try? Data(contentsOf: ageURL) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private func saveAges(_ ages: [String: Date]) {
        guard let data = try? JSONEncoder().encode(ages) else { return }
        try? data.write(to: ageURL, options: .atomic)
    }
}
