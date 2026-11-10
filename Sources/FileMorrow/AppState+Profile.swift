import AppKit
import Foundation
import UniformTypeIdentifiers

// Categories, teaching and the organization profile.
extension AppState {
    func setClassificationMode(_ mode: ClassificationMode) async {
        guard mode != classificationMode else { return }
        // Rescanning replaces `files` wholesale, so the analysis run has to be
        // fully stopped first rather than merely asked to stop.
        if isAnalyzing {
            cancelAnalysis()
            await analysisTask?.value
        }
        classificationMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "classificationMode")
        await scan()
    }

    func correctSelected(to category: ArchiveCategory) async {
        guard let id = selectedFileID, let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].category = category
        files[index].confidence = 100
        files[index].reason = "Confirmed by you"
        files[index].source = .user
        try? await saveDecision(for: files[index])
        status = "Saved your correction"
    }

    func teach(
        fileID: String,
        category: ArchiveCategory,
        filenameKeyword: String,
        rememberExtension: Bool
    ) async {
        guard let fileIndex = files.firstIndex(where: { $0.id == fileID }),
              let categoryIndex = profile.categories.firstIndex(where: { $0.category == category }),
              category != .needsReview else { return }

        let filename = files[fileIndex].name
        let keyword = filenameKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty,
           !profile.categories[categoryIndex].filenameKeywords.contains(where: {
               $0.caseInsensitiveCompare(keyword) == .orderedSame
           }) {
            profile.categories[categoryIndex].filenameKeywords.append(keyword)
        }
        if !profile.categories[categoryIndex].examples.contains(where: {
            $0.caseInsensitiveCompare(filename) == .orderedSame
        }) {
            profile.categories[categoryIndex].examples.append(filename)
        }

        let ext = RuleClassifier.normalizedExtension(files[fileIndex].url)
        if rememberExtension, !ext.isEmpty {
            for index in profile.categories.indices {
                profile.categories[index].extensions.removeAll {
                    $0.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                        .caseInsensitiveCompare(ext) == .orderedSame
                }
            }
            profile.categories[categoryIndex].extensions.append(ext)
        }

        files[fileIndex].category = category
        files[fileIndex].confidence = 100
        files[fileIndex].reason = "Confirmed by you and added to the organization profile"
        files[fileIndex].source = .user
        do {
            try await profileStore.save(profile)
            try await saveDecision(for: files[fileIndex])
            status = rememberExtension || !keyword.isEmpty
                ? "Correction saved • Future matching files will use it"
                : "Correction saved • Example added for Apple Intelligence"
        } catch {
            lastError = error.localizedDescription
            status = "Could not save teaching rule"
        }
    }

    func setCategoryEnabled(_ id: String, enabled: Bool) async {
        guard let index = profile.categories.firstIndex(where: { $0.id == id }),
              profile.categories[index].category != .needsReview else { return }
        profile.categories[index].enabled = enabled
        await persistProfileAndRescan()
    }

    func upsertCategory(_ definition: CategoryDefinition) async {
        if let index = profile.categories.firstIndex(where: { $0.id == definition.id }) {
            profile.categories[index] = definition
        } else {
            let insertionIndex = profile.categories.firstIndex { $0.category == .needsReview }
                ?? profile.categories.endIndex
            profile.categories.insert(definition, at: insertionIndex)
        }
        await persistProfileAndRescan()
    }

    func removeCategory(_ id: String) async {
        guard id != ArchiveCategory.needsReview.rawValue else { return }
        profile.categories.removeAll { $0.id == id }
        await persistProfileAndRescan()
    }

    func importProfile(from url: URL) async {
        do {
            profile = try await profileStore.importProfile(from: url)
            status = "Imported \(profile.name) profile"
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Profile import failed"
        }
    }

    func exportProfile(to url: URL) async {
        do {
            try await profileStore.export(profile, to: url)
            status = "Exported organization profile"
        } catch {
            lastError = error.localizedDescription
            status = "Profile export failed"
        }
    }

    private func persistProfileAndRescan() async {
        do {
            try await profileStore.save(profile)
            status = "Saved profile changes"
            await scan()
        } catch {
            lastError = error.localizedDescription
            status = "Could not save profile"
        }
    }
}
