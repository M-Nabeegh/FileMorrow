import Foundation
import PDFKit
@preconcurrency import Vision
import ImageIO
import UniformTypeIdentifiers

actor ContentExtractor {
    private let characterLimit = 4_000

    func extract(from url: URL, contentType: UTType?) async -> String {
        let ext = url.pathExtension.lowercased()
        var pieces = ["Filename: \(url.lastPathComponent)"]

        if ext == "pdf", let pdf = PDFDocument(url: url) {
            for index in 0..<min(pdf.pageCount, 4) {
                if let text = pdf.page(at: index)?.string { pieces.append(text) }
                if pieces.joined().count >= characterLimit { break }
            }
        } else if ["docx", "pptx", "xlsx"].contains(ext) {
            pieces.append(contentsOf: officeText(from: url, extension: ext))
        } else if ["zip"].contains(ext) {
            pieces.append("Archive entries:\n\(archiveListing(url))")
        } else if contentType?.conforms(to: .image) == true {
            pieces.append(await imageText(url))
        } else if ["txt", "md", "csv", "json", "swift", "py", "js", "ts", "sql", "rtf"].contains(ext),
                  let handle = try? FileHandle(forReadingFrom: url) {
            let data = try? handle.read(upToCount: 24_000)
            try? handle.close()
            if let data, let text = String(data: data, encoding: .utf8) { pieces.append(text) }
        }

        return String(pieces.joined(separator: "\n\n").prefix(characterLimit))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func officeText(from url: URL, extension ext: String) -> [String] {
        let entries = archiveListing(url).split(separator: "\n").map(String.init)
        let preferred: [String]
        switch ext {
        case "docx": preferred = entries.filter { $0.hasPrefix("word/") && $0.hasSuffix(".xml") }
        case "pptx": preferred = entries.filter { $0.contains("ppt/slides/slide") && $0.hasSuffix(".xml") }
        default: preferred = entries.filter { ($0.contains("xl/sharedStrings") || $0.contains("xl/worksheets/sheet")) && $0.hasSuffix(".xml") }
        }

        return preferred.prefix(5).compactMap { entry in
            guard let xml = run("/usr/bin/unzip", ["-p", url.path, entry]) else { return nil }
            return xml
                .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
        }
    }

    private func archiveListing(_ url: URL) -> String {
        run("/usr/bin/unzip", ["-Z1", url.path]).map { String($0.prefix(3_000)) } ?? ""
    }

    private func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = try pipe.fileHandleForReading.read(upToCount: 64_000) ?? Data()
            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()
            guard !data.isEmpty else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            if process.isRunning {
                process.terminate()
            }
            return nil
        }
    }

    private func imageText(_ url: URL) async -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { return "" }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ") ?? ""
                continuation.resume(returning: String(text.prefix(2_000)))
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .utility).async {
                try? VNImageRequestHandler(cgImage: image).perform([request])
            }
        }
    }
}
