import CryptoKit
import Foundation

actor DuplicateScanner {
    private struct CacheEntry {
        let size: Int64
        let modifiedAt: Date
        let hash: String
    }

    private var hashCache: [String: CacheEntry] = [:]

    func scan(
        root: URL,
        progress: (@Sendable (DuplicateScanProgress) async -> Void)? = nil
    ) async -> [DuplicateGroup] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            .contentModificationDateKey, .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var bySize: [Int64: [URL]] = [:]
        while let url = enumerator.nextObject() as? URL {
            guard !Task.isCancelled else { return [] }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  values.isUbiquitousItem != true
                    || values.ubiquitousItemDownloadingStatus == URLUbiquitousItemDownloadingStatus.current,
                  let size = values.fileSize,
                  size > 0 else { continue }
            bySize[Int64(size), default: []].append(url)
        }

        let candidates = bySize.filter { $0.value.count > 1 }.flatMap(\.value)
        let fingerprintBytes = candidates.reduce(Int64(0)) {
            $0 + min(Int64(262_144), fileSize($1))
        }
        let possibleFullHashBytes = candidates.reduce(Int64(0)) { $0 + fileSize($1) }
        let totalWorkBytes = max(1, fingerprintBytes + possibleFullHashBytes)
        var processedBytes: Int64 = 0
        var completedFiles = 0

        var groups: [DuplicateGroup] = []
        for (size, urls) in bySize where urls.count > 1 {
            guard !Task.isCancelled else { return [] }
            var byFingerprint: [String: [URL]] = [:]
            for url in urls {
                guard !Task.isCancelled else { return [] }
                guard let fingerprint = quickFingerprint(url, size: size) else { continue }
                byFingerprint[fingerprint, default: []].append(url)
                processedBytes += min(size, 262_144)
                completedFiles += 1
                await progress?(.init(
                    stage: .fingerprinting,
                    completedFiles: completedFiles,
                    totalFiles: candidates.count * 2,
                    processedBytes: processedBytes,
                    totalBytes: totalWorkBytes,
                    currentFile: url.lastPathComponent
                ))
            }

            for matches in byFingerprint.values where matches.count > 1 {
                var byHash: [String: [URL]] = [:]
                for url in matches {
                    guard !Task.isCancelled else { return [] }
                    guard let hash = fullHash(url, size: size) else { continue }
                    byHash[hash, default: []].append(url)
                    processedBytes += size
                    completedFiles += 1
                    await progress?(.init(
                        stage: .verifying,
                        completedFiles: completedFiles,
                        totalFiles: candidates.count * 2,
                        processedBytes: processedBytes,
                        totalBytes: totalWorkBytes,
                        currentFile: url.lastPathComponent
                    ))
                }
                for (hash, exactMatches) in byHash where exactMatches.count > 1 {
                    let ordered = exactMatches.sorted {
                        $0.path.localizedStandardCompare($1.path) == .orderedAscending
                    }
                    groups.append(.init(id: hash, files: ordered, fileSize: size))
                }
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

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
    }

    private func quickFingerprint(_ url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            let sampleSize = min(Int64(131_072), size)
            if let first = try handle.read(upToCount: Int(sampleSize)) {
                hasher.update(data: first)
            }
            if size > sampleSize {
                try handle.seek(toOffset: UInt64(max(0, size - sampleSize)))
                if let last = try handle.read(upToCount: Int(sampleSize)) {
                    hasher.update(data: last)
                }
            }
            hasher.update(data: Data(String(size).utf8))
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            return nil
        }
    }

    private func fullHash(_ url: URL, size: Int64) -> String? {
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        if let cached = hashCache[url.path],
           cached.size == size,
           cached.modifiedAt == modifiedAt {
            return cached.hash
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while !Task.isCancelled,
                  let data = try handle.read(upToCount: 1_048_576),
                  !data.isEmpty {
                hasher.update(data: data)
            }
            guard !Task.isCancelled else { return nil }
            let hash = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            hashCache[url.path] = .init(size: size, modifiedAt: modifiedAt, hash: hash)
            return hash
        } catch {
            return nil
        }
    }

}
