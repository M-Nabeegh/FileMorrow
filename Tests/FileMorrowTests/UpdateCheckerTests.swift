import Foundation
import XCTest
@testable import FileMorrow

private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: UpdateChecker.latestReleaseEndpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
}

final class UpdateCheckerTests: XCTestCase {
    private func release(tag: String, page: String = "https://github.com/M-Nabeegh/FileMorrow/releases/tag/v1.9.0", extra: String = "") -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(page)"\#(extra)}"#.utf8)
    }

    func testVersionsCompareNumberByNumber() {
        XCTAssertTrue(UpdateChecker.isNewer("1.9.0", than: "1.8.0"))
        XCTAssertTrue(UpdateChecker.isNewer("v1.10", than: "1.9.3"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.99.99"))
        XCTAssertTrue(UpdateChecker.isNewer("1.8.1", than: "1.8"))
        XCTAssertFalse(UpdateChecker.isNewer("1.8", than: "1.8.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.7.1", than: "1.8.0"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9.0-beta", than: "1.8.0"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.8.0"))
    }

    func testANewerReleaseIsOffered() async {
        let body = release(tag: "v1.9.0")
        let result = await UpdateChecker.check(currentVersion: "1.8.0") { _ in (body, response(200)) }

        XCTAssertEqual(result, .available(ReleaseInfo(
            version: "1.9.0",
            page: URL(string: "https://github.com/M-Nabeegh/FileMorrow/releases/tag/v1.9.0")!
        )))
    }

    func testTheSameOrAnOlderReleaseMeansUpToDate() async {
        let same = release(tag: "v1.8.0")
        let older = release(tag: "v1.7.1")
        let first = await UpdateChecker.check(currentVersion: "1.8.0") { _ in (same, response(200)) }
        let second = await UpdateChecker.check(currentVersion: "1.8.0") { _ in (older, response(200)) }

        XCTAssertEqual(first, .upToDate(current: "1.8.0"))
        XCTAssertEqual(second, .upToDate(current: "1.8.0"))
    }

    func testDraftsAndPrereleasesAreIgnored() {
        XCTAssertNil(UpdateChecker.latestRelease(in: release(tag: "v2.0.0", extra: #","prerelease":true"#)))
        XCTAssertNil(UpdateChecker.latestRelease(in: release(tag: "v2.0.0", extra: #","draft":true"#)))
        XCTAssertNil(UpdateChecker.latestRelease(in: release(tag: "nightly")))
        XCTAssertNil(UpdateChecker.latestRelease(in: Data("not json".utf8)))
    }

    func testOnlyPagesInsideTheRepositoryAreOpened() {
        let fallback = UpdateChecker.releasesPage
        XCTAssertEqual(UpdateChecker.trustedPage("https://evil.example/M-Nabeegh/FileMorrow/releases/tag/v9"), fallback)
        XCTAssertEqual(UpdateChecker.trustedPage("http://github.com/M-Nabeegh/FileMorrow/releases/tag/v9"), fallback)
        XCTAssertEqual(UpdateChecker.trustedPage("https://github.com/someone/else/releases/tag/v9"), fallback)
        XCTAssertEqual(UpdateChecker.trustedPage(nil), fallback)
        XCTAssertEqual(
            UpdateChecker.trustedPage("https://github.com/M-Nabeegh/FileMorrow/releases/tag/v1.9.0").absoluteString,
            "https://github.com/M-Nabeegh/FileMorrow/releases/tag/v1.9.0"
        )
    }

    func testFailuresAreReportedWithoutThrowing() async {
        let limited = await UpdateChecker.check(currentVersion: "1.8.0") { _ in (Data(), response(403)) }
        let offline = await UpdateChecker.check(currentVersion: "1.8.0") { _ in throw URLError(.notConnectedToInternet) }
        let garbled = await UpdateChecker.check(currentVersion: "1.8.0") { _ in (Data("{}".utf8), response(200)) }

        XCTAssertEqual(limited, .failed("GitHub answered with status 403. Try again later."))
        XCTAssertEqual(offline, .failed("FileMorrow could not reach GitHub. Check your connection and try again."))
        XCTAssertEqual(garbled, .failed("The release information from GitHub could not be read."))
    }

    func testTheRequestCarriesNoCookiesAndGoesOnlyToGitHub() async {
        let seen = RequestBox()
        let body = release(tag: "v1.8.0")
        _ = await UpdateChecker.check(currentVersion: "1.8.0") { request in
            await seen.set(request)
            return (body, response(200))
        }

        let request = await seen.value
        XCTAssertEqual(request?.url?.host, "api.github.com")
        XCTAssertEqual(request?.url?.path, "/repos/M-Nabeegh/FileMorrow/releases/latest")
        XCTAssertEqual(request?.httpMethod, "GET")
        XCTAssertEqual(request?.httpShouldHandleCookies, false)
        XCTAssertNil(request?.httpBody)
    }

    func testAutomaticChecksWaitADayBetweenRuns() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(UpdateChecker.isDue(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-3_600), now: now))
        XCTAssertTrue(UpdateChecker.isDue(lastCheck: now.addingTimeInterval(-86_400), now: now))
    }
}

private actor RequestBox {
    private(set) var value: URLRequest?
    func set(_ request: URLRequest) { value = request }
}
