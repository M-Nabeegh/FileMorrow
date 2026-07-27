import CoreGraphics
import CoreText
import XCTest
import UniformTypeIdentifiers
@testable import DownloadsButler

final class SyntheticAccuracyTests: XCTestCase {
    func testPrivacySafeSyntheticOfficeSuite() async throws {
        let fixture = try SyntheticFixture()
        defer { fixture.remove() }

        let cases: [(URL, UTType?, ArchiveCategory)] = [
            (
                try fixture.pdf(
                    named: "report-0041.pdf",
                    text: "Fictional bank statement balance sheet cash flow portfolio"
                ),
                .pdf,
                .finance
            ),
            (
                try fixture.officeArchive(
                    named: "deck-final.pptx",
                    entry: "ppt/slides/slide1.xml",
                    text: "University lecture coursework neural network algorithm"
                ),
                UTType(filenameExtension: "pptx"),
                .university
            ),
            (
                try fixture.officeArchive(
                    named: "records-2026.xlsx",
                    entry: "xl/sharedStrings.xml",
                    text: "Fictional patient clinical diagnosis treatment hospital"
                ),
                UTType(filenameExtension: "xlsx"),
                .medical
            )
        ]

        var correct = 0
        for (url, type, expected) in cases {
            let evidence = await ContentExtractor().extract(from: url, contentType: type)
            let decision = EvidenceClassifier.classify(evidence, profile: TestProfiles.general)
            if decision?.category == expected { correct += 1 }
        }

        XCTAssertEqual(correct, cases.count, "Synthetic accuracy regression: \(correct)/\(cases.count)")
    }

    func testAmbiguousFilenameAndContentRemainUncertain() async throws {
        let fixture = try SyntheticFixture()
        defer { fixture.remove() }
        let url = try fixture.pdf(named: "scan-000184.pdf", text: "Reference number 184. General notes.")

        let evidence = await ContentExtractor().extract(from: url, contentType: .pdf)

        XCTAssertNil(EvidenceClassifier.classify(evidence, profile: TestProfiles.general))
    }

    func testAllAppleCompatibilityStatesHaveActionableCopy() {
        for state in IntelligenceAvailabilityState.allCases {
            XCTAssertFalse(state.title.isEmpty)
            XCTAssertFalse(state.detail.isEmpty)
        }

        XCTAssertTrue(IntelligenceAvailabilityState.available.isReady)
        XCTAssertFalse(IntelligenceAvailabilityState.appleIntelligenceNotEnabled.isReady)
        XCTAssertFalse(IntelligenceAvailabilityState.deviceNotEligible.isReady)
        XCTAssertFalse(IntelligenceAvailabilityState.modelNotReady.isReady)
        XCTAssertTrue(IntelligenceAvailabilityState.modelNotReady.detail.contains("Format mode"))
    }
}

private final class SyntheticFixture {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "FileMorrow-Synthetic-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func pdf(named name: String, text: String) throws -> URL {
        let url = root.appending(path: name)
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw FixtureError.creationFailed
        }

        context.beginPDFPage(nil)
        context.textMatrix = .identity
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 16, nil)
            ])
        )
        context.textPosition = CGPoint(x: 54, y: 72)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    func officeArchive(named name: String, entry: String, text: String) throws -> URL {
        let staging = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let entryURL = staging.appending(path: entry)
        try FileManager.default.createDirectory(
            at: entryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("<root><text>\(text)</text></root>".utf8).write(to: entryURL)

        let archive = root.appending(path: name)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", archive.path, entry.components(separatedBy: "/").first ?? entry]
        process.currentDirectoryURL = staging
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw FixtureError.creationFailed }
        return archive
    }

    enum FixtureError: Error {
        case creationFailed
    }
}
