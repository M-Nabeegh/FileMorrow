import XCTest
import UniformTypeIdentifiers
@testable import DownloadsButler

final class ContentExtractorTests: XCTestCase {
    func testPlainTextEvidenceIncludesFilenameAndContents() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appending(path: "lecture-notes.txt")
        try Data("neural networks backpropagation".utf8).write(to: file)

        let evidence = await ContentExtractor().extract(from: file, contentType: .plainText)
        XCTAssertTrue(evidence.contains("lecture-notes.txt"))
        XCTAssertTrue(evidence.contains("neural networks backpropagation"))
    }

    func testEvidenceIsBounded() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appending(path: "large.txt")
        try Data(String(repeating: "private local evidence ", count: 1_000).utf8).write(to: file)

        let evidence = await ContentExtractor().extract(from: file, contentType: .plainText)
        XCTAssertLessThanOrEqual(evidence.count, 4_000)
    }

    func testLargeOfficeXMLDoesNotBlockExtraction() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: folder.appending(path: "word", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }

        let xml = "<document><text>" + String(repeating: "university coursework ", count: 20_000) + "</text></document>"
        try Data(xml.utf8).write(to: folder.appending(path: "word/document.xml"))

        let archive = folder.appending(path: "large.docx")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", archive.path, "word"]
        process.currentDirectoryURL = folder
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let evidence = await ContentExtractor().extract(
            from: archive,
            contentType: UTType(filenameExtension: "docx")
        )
        XCTAssertTrue(evidence.contains("university coursework"))
        XCTAssertLessThanOrEqual(evidence.count, 4_000)
    }
}
