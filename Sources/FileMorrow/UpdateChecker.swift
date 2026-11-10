import Foundation

struct ReleaseInfo: Equatable, Sendable {
    let version: String
    let page: URL
}

enum UpdateCheckResult: Equatable, Sendable {
    case upToDate(current: String)
    case available(ReleaseInfo)
    case failed(String)
}

/// Asks GitHub which FileMorrow release is the latest.
///
/// This is the app's only network request. It is a single GET with no cookies, no identifiers and
/// nothing about the user's files, and it runs only when the user chooses Check for Updates or has
/// turned on automatic checks in Settings.
enum UpdateChecker {
    static let latestReleaseEndpoint = URL(string: "https://api.github.com/repos/M-Nabeegh/FileMorrow/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/M-Nabeegh/FileMorrow/releases/latest")!
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static func check(
        currentVersion: String,
        fetch: Fetch = { try await URLSession(configuration: .ephemeral).data(for: $0) }
    ) async -> UpdateCheckResult {
        var request = URLRequest(url: latestReleaseEndpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("FileMorrow", forHTTPHeaderField: "User-Agent")
        request.httpShouldHandleCookies = false

        do {
            let (data, response) = try await fetch(request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return .failed("GitHub answered with status \(http.statusCode). Try again later.")
            }
            guard let release = latestRelease(in: data) else {
                return .failed("The release information from GitHub could not be read.")
            }
            return isNewer(release.version, than: currentVersion)
                ? .available(release)
                : .upToDate(current: currentVersion)
        } catch {
            return .failed("FileMorrow could not reach GitHub. Check your connection and try again.")
        }
    }

    /// Reads the tag and page of a published release. Drafts and pre-releases are ignored.
    static func latestRelease(in data: Data) -> ReleaseInfo? {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String?
            let draft: Bool?
            let prerelease: Bool?
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.draft != true, payload.prerelease != true else { return nil }
        let version = normalized(payload.tag_name)
        guard !components(version).isEmpty else { return nil }
        return ReleaseInfo(version: version, page: trustedPage(payload.html_url))
    }

    /// Only ever opens a page inside the FileMorrow repository, whatever the response says.
    static func trustedPage(_ candidate: String?) -> URL {
        guard let candidate, let url = URL(string: candidate),
              url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/M-Nabeegh/FileMorrow/releases/") else { return releasesPage }
        return url
    }

    /// Compares dotted versions number by number, so 1.10 is newer than 1.9 and 1.8 equals 1.8.0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(normalized(candidate))
        let rhs = components(normalized(current))
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    static func isDue(lastCheck: Date?, now: Date = .now) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= automaticInterval
    }

    private static func normalized(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
    }

    /// Empty when any part is not a plain number, which makes the version incomparable.
    private static func components(_ version: String) -> [Int] {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == parts.count ? numbers : []
    }
}
