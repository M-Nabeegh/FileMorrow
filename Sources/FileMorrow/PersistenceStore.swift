import Foundation

actor PersistenceStore {
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private let decisionsURL: URL
    private let movesURL: URL

    init(baseURL: URL? = nil) {
        let base = baseURL ?? AppSupportPaths.directory()
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        decisionsURL = base.appending(path: "decisions.json")
        movesURL = base.appending(path: "move-history.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func decisions() -> [String: SavedDecision] {
        guard let data = try? Data(contentsOf: decisionsURL) else { return [:] }
        return (try? decoder.decode([String: SavedDecision].self, from: data)) ?? [:]
    }

    func save(_ decision: SavedDecision) throws {
        var all = decisions()
        all[decision.path] = decision
        try encoder.encode(all).write(to: decisionsURL, options: .atomic)
    }

    func history() -> [MoveBatch] {
        guard let data = try? Data(contentsOf: movesURL) else { return [] }
        return (try? decoder.decode([MoveBatch].self, from: data)) ?? []
    }

    func append(_ batch: MoveBatch) throws {
        var all = history()
        all.append(batch)
        try encoder.encode(all).write(to: movesURL, options: .atomic)
    }

    func removeLastBatch() throws {
        var all = history()
        guard !all.isEmpty else { return }
        all.removeLast()
        try encoder.encode(all).write(to: movesURL, options: .atomic)
    }

    func replaceLastBatch(with batch: MoveBatch?) throws {
        var all = history()
        guard !all.isEmpty else { return }
        all.removeLast()
        if let batch { all.append(batch) }
        try encoder.encode(all).write(to: movesURL, options: .atomic)
    }
}
