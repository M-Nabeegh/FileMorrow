import Foundation

actor OrganizerService {
    private let store: PersistenceStore

    init(store: PersistenceStore) {
        self.store = store
    }

    func organize(
        _ records: [FileRecord],
        downloadsURL: URL,
        minimumConfidence: Int,
        profile: OrganizationProfile
    ) async throws -> Int {
        var operations: [MoveOperation] = []
        var firstError: Error?

        for record in records where record.confidence >= minimumConfidence && record.category != .needsReview {
            do {
                let folderName = profile.definition(for: record.category)?.folderName
                    ?? record.category.rawValue
                let folder = downloadsURL.appending(path: folderName, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let marker = folder.appending(path: ".downloads-butler-managed")
                if !FileManager.default.fileExists(atPath: marker.path) {
                    try Data("Managed by FileMorrow\n".utf8).write(to: marker, options: .atomic)
                }
                let destination = uniqueDestination(for: record.url, in: folder)
                try FileManager.default.moveItem(at: record.url, to: destination)
                operations.append(.init(originalPath: record.url.path, destinationPath: destination.path))
            } catch {
                firstError = error
                break
            }
        }

        if !operations.isEmpty {
            try await store.append(.init(id: UUID(), createdAt: .now, operations: operations))
        }
        if let firstError { throw firstError }
        return operations.count
    }

    func undoLast() async throws -> Int {
        guard let batch = await store.history().last else { return 0 }
        var count = 0
        var remaining: [MoveOperation] = []
        for operation in batch.operations.reversed() {
            let from = URL(fileURLWithPath: operation.destinationPath)
            let to = URL(fileURLWithPath: operation.originalPath)
            guard FileManager.default.fileExists(atPath: from.path) else { continue }
            guard !FileManager.default.fileExists(atPath: to.path) else {
                remaining.append(operation)
                continue
            }
            do {
                try FileManager.default.moveItem(at: from, to: to)
                count += 1
            } catch {
                remaining.append(operation)
            }
        }
        let unresolved = remaining.isEmpty
            ? nil
            : MoveBatch(id: batch.id, createdAt: batch.createdAt, operations: Array(remaining.reversed()))
        try await store.replaceLastBatch(with: unresolved)
        return count
    }

    private func uniqueDestination(for source: URL, in folder: URL) -> URL {
        var candidate = folder.appending(path: source.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            let name = ext.isEmpty ? "\(stem) \(suffix)" : "\(stem) \(suffix).\(ext)"
            candidate = folder.appending(path: name)
            suffix += 1
        }
        return candidate
    }
}
