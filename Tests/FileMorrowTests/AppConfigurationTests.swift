import AppKit
import Foundation
import XCTest
@testable import FileMorrow

@MainActor
final class AppConfigurationTests: XCTestCase {
    func testDockPreferenceMapsToExpectedActivationPolicy() {
        XCTAssertEqual(DockVisibility.policy(keepInDock: true), .regular)
        XCTAssertEqual(DockVisibility.policy(keepInDock: false), .accessory)
    }

    func testLegacyApplicationSupportIsMigrated() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let legacy = root.appending(path: "DownloadsButler", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("saved".utf8).write(to: legacy.appending(path: "decisions.json"))
        defer { try? FileManager.default.removeItem(at: root) }

        let migrated = AppSupportPaths.directory(applicationSupportDirectory: root)

        XCTAssertEqual(migrated.lastPathComponent, "FileMorrow")
        XCTAssertTrue(FileManager.default.fileExists(atPath: migrated.appending(path: "decisions.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testCurrentAndLegacyManagedMarkersAreRecognized() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyFolder = root.appending(path: "Legacy", directoryHint: .isDirectory)
        let currentFolder = root.appending(path: "Current", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: currentFolder, withIntermediateDirectories: true)
        try Data().write(to: legacyFolder.appending(path: AppSupportPaths.legacyManagedMarkerName))
        try Data().write(to: currentFolder.appending(path: AppSupportPaths.managedMarkerName))

        XCTAssertTrue(AppSupportPaths.hasManagedMarker(in: legacyFolder))
        XCTAssertTrue(AppSupportPaths.hasManagedMarker(in: currentFolder))
    }
}
