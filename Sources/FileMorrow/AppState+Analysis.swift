import AppKit
import Foundation
import UniformTypeIdentifiers

// Smart Content analysis.
extension AppState {
    func analyzeReady(limit: Int? = nil) async {
        guard !isWorking else { return }
        guard classificationMode == .smartContent else {
            status = "Switch to Smart Content in Settings to use Apple Intelligence"
            return
        }
        guard intelligenceReady else {
            status = "Apple Intelligence is not available on this Mac"
            lastError = intelligenceStatusDetail
            return
        }
        // Identify work by file id, never by array index: `files` is replaced
        // wholesale by any rescan, and this loop suspends on extraction and on
        // the model. An index captured before an await can point at a
        // different file — or past the end of the array — once it resumes.
        let candidates = files.filter(needsAnalysis).map(\.id)
        let selected = limit.map { Array(candidates.prefix($0)) } ?? candidates
        guard !selected.isEmpty else {
            status = "Nothing needs AI analysis"
            return
        }

        isWorking = true
        isAnalyzing = true
        shouldCancelAnalysis = false
        lastError = nil
        defer {
            isWorking = false
            isAnalyzing = false
            progress = nil
        }

        var completed = 0
        var pendingDecisions: [SavedDecision] = []
        for id in selected {
            guard !Task.isCancelled, !shouldCancelAnalysis else { break }
            guard let record = files.first(where: { $0.id == id }) else { continue }
            status = "Reading \(record.name)…"
            let type = UTType(record.contentType)
            let excerpt = await extractor.extract(from: record.url, contentType: type)

            if let localDecision = EvidenceClassifier.classify(excerpt, profile: profile) {
                if let updated = apply(to: id, excerpt: excerpt, {
                    $0.category = localDecision.category
                    $0.confidence = localDecision.confidence
                    $0.reason = localDecision.reason
                    $0.source = .localContent
                }) {
                    pendingDecisions.append(decision(for: updated))
                }
                completed += 1
                progress = Double(completed) / Double(selected.count)
                continue
            }

            do {
                status = "Apple Intelligence • \(completed + 1) of \(selected.count)"
                let (result, definition) = try await ai.classify(
                    filename: record.name,
                    excerpt: excerpt,
                    categories: profile.enabledCategories
                )
                let category = definition.category
                if let updated = apply(to: id, excerpt: excerpt, { file in
                    if category == .needsReview, record.category != .needsReview {
                        file.category = record.category
                        file.confidence = max(record.confidence, self.minimumConfidence)
                        file.reason = "Known \(self.definition(for: record.category).name) format; no stronger subject was found"
                        file.source = .formatFallback
                    } else {
                        file.category = category
                        file.confidence = category == .needsReview ? min(result.confidence, 59) : result.confidence
                        file.reason = self.cleanReason(result.reason, category: category)
                        file.source = .appleAI
                    }
                }) {
                    pendingDecisions.append(decision(for: updated))
                }
            } catch {
                // A temporary model failure must never erase a useful format rule.
                if let index = files.firstIndex(where: { $0.id == id }) {
                    files[index] = record
                }
                lastError = error.localizedDescription
            }
            completed += 1
            progress = Double(completed) / Double(selected.count)
        }

        // One write for the whole run instead of a full re-encode per file.
        if !pendingDecisions.isEmpty {
            try? await store.save(contentsOf: pendingDecisions)
        }
        status = shouldCancelAnalysis
            ? "Stopped after \(completed) files • Decisions saved"
            : "Analyzed \(completed) files • No files moved"
    }

    /// Owns the analysis task so other workflows can wait for it to finish
    /// instead of racing a run that is still winding down.
    func startAnalysis(limit: Int? = nil) {
        guard !isWorking else { return }
        analysisTask = Task { [weak self] in await self?.analyzeReady(limit: limit) }
    }

    func cancelAnalysis() {
        shouldCancelAnalysis = true
        status = "Stopping after the current file…"
    }

    func needsAnalysis(_ record: FileRecord) -> Bool {
        !record.isOrganized
            && record.dateAdded < cutoffDate
            && record.source == .rule
            && (record.confidence < minimumConfidence || record.category == .archives)
    }

    /// Re-resolves a file by id and mutates it in place. Returns nil when the
    /// file disappeared from the list while the caller was suspended.
    private func apply(
        to id: String,
        excerpt: String,
        _ mutate: (inout FileRecord) -> Void
    ) -> FileRecord? {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return nil }
        mutate(&files[index])
        files[index].excerpt = excerpt
        return files[index]
    }
}
