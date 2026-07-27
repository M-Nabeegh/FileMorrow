import XCTest
@testable import DownloadsButler

final class EvidenceClassifierTests: XCTestCase {
    func testFinancialEvidenceIsClassifiedLocally() {
        let evidence = "Annual financial statement with balance sheet, cash flow and dividend information."
        let result = EvidenceClassifier.classify(evidence, profile: TestProfiles.general)
        XCTAssertEqual(result?.category, .finance)
        XCTAssertGreaterThanOrEqual(result?.confidence ?? 0, 85)
    }

    func testMedicalEvidenceIsClassifiedLocally() {
        let evidence = "Patient discharge from hospital after urology surgery and clinical treatment."
        XCTAssertEqual(EvidenceClassifier.classify(evidence, profile: TestProfiles.general)?.category, .medical)
    }

    func testAmbiguousEvidenceStillUsesAppleIntelligence() {
        XCTAssertNil(EvidenceClassifier.classify("A short update with no clear subject.", profile: TestProfiles.general))
    }

    func testMixedWeakEvidenceRemainsAmbiguous() {
        XCTAssertNil(EvidenceClassifier.classify("A lecture about a hospital and a bank.", profile: TestProfiles.general))
    }
}
