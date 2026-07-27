import Foundation
import XCTest
@testable import DownloadsButler

final class OrganizerServiceTests: XCTestCase {
    func testMarkerCollisionAndUndoAreSafe() async throws {
        let root = temporaryDirectory()
        let state = root.appending(path: "State", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appending(path: "photo.jpg")
        try Data("new".utf8).write(to: source)
        let images = root.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: images.appending(path: "photo.jpg"))

        let store = PersistenceStore(baseURL: state)
        let organizer = OrganizerService(store: store)
        let moved = try await organizer.organize(
            [record(url: source)],
            downloadsURL: root,
            minimumConfidence: 85,
            profile: TestProfiles.general
        )

        XCTAssertEqual(moved, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appending(path: ".downloads-butler-managed").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: images.appending(path: "photo 2.jpg").path))
        XCTAssertEqual(try Data(contentsOf: images.appending(path: "photo.jpg")), Data("existing".utf8))

        let undone = try await organizer.undoLast()
        XCTAssertEqual(undone, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: images.appending(path: "photo 2.jpg").path))
    }

    private func record(url: URL) -> FileRecord {
        FileRecord(
            url: url,
            dateAdded: .distantPast,
            size: 3,
            contentType: "public.jpeg",
            category: .images,
            confidence: 100,
            reason: "Known image format",
            source: .rule,
            excerpt: nil,
            location: .loose
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
    }
}
