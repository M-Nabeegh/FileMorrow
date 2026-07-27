import Foundation
import XCTest
@testable import FileMorrow

final class DuplicateScannerTests: XCTestCase {
    func testFindsOnlyByteIdenticalFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let duplicate = Data("same bytes".utf8)
        try duplicate.write(to: root.appending(path: "copy-a.txt"))
        try duplicate.write(to: root.appending(path: "copy-b.txt"))
        try Data("different!".utf8).write(to: root.appending(path: "different.txt"))

        let groups = await DuplicateScanner().scan(root: root)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].extras.count, 1)
        XCTAssertEqual(groups[0].wastedSize, Int64(duplicate.count))
    }

    func testFindsExactDuplicatesInsideDownloadedOrUserCreatedFolders() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let firstFolder = root.appending(path: "Downloaded Project", directoryHint: .isDirectory)
        let secondFolder = root.appending(path: "Personal Folder", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let duplicate = Data("nested duplicate".utf8)
        try duplicate.write(to: firstFolder.appending(path: "copy-a.txt"))
        try duplicate.write(to: secondFolder.appending(path: "copy-b.txt"))

        let groups = await DuplicateScanner().scan(root: root)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertTrue(groups[0].files.allSatisfy { $0.deletingLastPathComponent() != root })
    }

    func testDuplicateCleanupKeepsOneAndUsesRecoverableDestination() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let recovery = root.appending(path: "Recovery Trash", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = Data("identical".utf8)
        try bytes.write(to: root.appending(path: "a.txt"))
        try bytes.write(to: root.appending(path: "b.txt"))
        let scanner = DuplicateScanner()
        let groups = await scanner.scan(root: root)
        let group = try XCTUnwrap(groups.first)

        let count = try await scanner.trashExtras(in: group) { source in
            try FileManager.default.moveItem(
                at: source,
                to: recovery.appending(path: source.lastPathComponent)
            )
        }

        XCTAssertEqual(count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: group.keeper.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: recovery.path).count, 1)
    }

    func testScanReportsFingerprintAndVerificationProgress() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let bytes = Data(repeating: 7, count: 300_000)
        try bytes.write(to: root.appending(path: "first.bin"))
        try bytes.write(to: root.appending(path: "second.bin"))

        let collector = ProgressCollector()
        let groups = await DuplicateScanner().scan(root: root) { update in
            await collector.append(update)
        }
        let stages = await collector.stages

        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(stages.contains(.fingerprinting))
        XCTAssertTrue(stages.contains(.verifying))
    }
}

private actor ProgressCollector {
    private var values: [DuplicateScanProgress] = []

    func append(_ value: DuplicateScanProgress) {
        values.append(value)
    }

    var stages: Set<DuplicateScanProgress.Stage> {
        Set(values.map(\.stage))
    }
}
