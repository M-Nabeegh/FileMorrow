import CryptoKit
import Foundation

actor DuplicateScanner {
    func scan(root: URL) -> [DuplicateGroup] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var bySize: [Int64: [URL]] = [:]
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size > 0 else { continue }
            bySize[Int64(size), default: []].append(url)
        }

        var groups: [DuplicateGroup] = []
        for (size, urls) in bySize where urls.count > 1 {
            var byHash: [String: [URL]] = [:]
            for url in urls {
                guard let hash = sha256(url) else { continue }
                byHash[hash, default: []].append(url)
            }
            for (hash, matches) in byHash where matches.count > 1 {
                let ordered = matches.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                groups.append(.init(id: hash, files: ordered, fileSize: size))
            }
        }
        return groups.sorted { $0.wastedSize > $1.wastedSize }
    }

    func trashExtras(
        in group: DuplicateGroup,
        trash: ((URL) throws -> Void)? = nil
    ) throws -> Int {
        var count = 0
        for url in group.extras where FileManager.default.fileExists(atPath: url.path) {
            if let trash {
                try trash(url)
            } else {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            }
            count += 1
        }
        return count
    }

    private func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

}
