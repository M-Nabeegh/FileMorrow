import Foundation
import XCTest
@testable import FileMorrow

final class ArchiveEligibilityTests: XCTestCase {
    func testLooseFileBecomesEligibleOnlyAfterSevenDays() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)

        XCTAssertFalse(ArchiveEligibility.isEligible(record(date: cutoff), cutoffDate: cutoff))
        XCTAssertTrue(ArchiveEligibility.isEligible(record(date: cutoff.addingTimeInterval(-1)), cutoffDate: cutoff))
        XCTAssertFalse(ArchiveEligibility.isEligible(record(date: now), cutoffDate: cutoff))
    }

    func testOrganizedFileIsNeverEligibleAgain() {
        let cutoff = Date()
        XCTAssertFalse(
            ArchiveEligibility.isEligible(
                record(date: .distantPast, location: .organized),
                cutoffDate: cutoff
            )
        )
    }

    private func record(date: Date, location: FileLocation = .loose) -> FileRecord {
        FileRecord(
            url: URL(fileURLWithPath: "/tmp/example.pdf"),
            dateAdded: date,
            size: 1,
            contentType: "com.adobe.pdf",
            category: .documents,
            confidence: 100,
            reason: "Test",
            source: .rule,
            excerpt: nil,
            location: location
        )
    }
}
