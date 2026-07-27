import XCTest
import UniformTypeIdentifiers
@testable import DownloadsButler

final class RuleClassifierTests: XCTestCase {
    func testMedicalSpreadsheetUsesMeaningBeforeExtension() {
        let url = URL(fileURLWithPath: "/tmp/clinical-cases.xlsx")
        XCTAssertEqual(RuleClassifier.classify(url: url, type: .spreadsheet, profile: TestProfiles.general).category, .medical)
    }

    func testVisaArchiveUsesMeaningBeforeContainer() {
        let url = URL(fileURLWithPath: "/tmp/golden visa.zip")
        XCTAssertEqual(RuleClassifier.classify(url: url, type: .zip, profile: TestProfiles.general).category, .travel)
    }

    func testAmbiguousPDFNeedsContentAnalysis() {
        let url = URL(fileURLWithPath: "/tmp/13072026155147113.pdf")
        let decision = RuleClassifier.classify(url: url, type: .pdf, profile: TestProfiles.general)
        XCTAssertEqual(decision.category, .documents)
        XCTAssertLessThan(decision.confidence, 85)
    }

    func testInstallerIsDeterministic() {
        let url = URL(fileURLWithPath: "/tmp/App.dmg")
        XCTAssertEqual(RuleClassifier.classify(url: url, type: .diskImage, profile: TestProfiles.general).category, .installers)
    }

    func testUnknownFormatsUseReviewFallback() {
        let url = URL(fileURLWithPath: "/tmp/unknown.blobthing")
        XCTAssertEqual(
            RuleClassifier.classify(url: url, type: nil, profile: TestProfiles.general).category,
            .needsReview
        )
    }

    func testFormatOnlyUsesOtherForUnknownFormats() {
        let url = URL(fileURLWithPath: "/tmp/unknown.blobthing")
        let decision = RuleClassifier.classify(
            url: url,
            type: nil,
            profile: TestProfiles.general,
            mode: .formatOnly
        )
        XCTAssertEqual(decision.category, .other)
        XCTAssertEqual(decision.confidence, 100)
    }

    func testExtendedGeneralFormatCatalog() {
        let cases: [(String, ArchiveCategory)] = [
            ("movie.srt", .documents),
            ("JetsamEvent.ips", .init(rawValue: "System & Diagnostics")),
            ("art.eps", .design),
            ("project.sb3", .init(rawValue: "Projects & Plugins")),
            ("plugin.tpp", .init(rawValue: "Projects & Plugins")),
            ("setup.exe", .installers),
            ("payment.php", .codeData),
            ("database.sqlite-wal", .codeData),
            ("slides.pptx", .documents),
            ("notebook.ipynb", .codeData),
            ("model.alp", .codeData),
            ("triples.rdf", .codeData),
            ("saved-page.webarchive", .documents)
        ]
        for (filename, expected) in cases {
            let result = RuleClassifier.classify(
                url: URL(fileURLWithPath: "/tmp/\(filename)"),
                type: nil,
                profile: TestProfiles.general
            )
            XCTAssertEqual(result.category, expected, filename)
            XCTAssertGreaterThanOrEqual(result.confidence, 60, filename)
        }
    }
}
