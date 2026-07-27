import Foundation

enum AppSupportPaths {
    static let managedMarkerName = ".filemorrow-managed"
    static let legacyManagedMarkerName = ".downloads-butler-managed"

    static func directory(
        fileManager: FileManager = .default,
        applicationSupportDirectory: URL? = nil
    ) -> URL {
        let applicationSupport = applicationSupportDirectory ?? fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let current = applicationSupport.appending(path: "FileMorrow", directoryHint: .isDirectory)
        let legacy = applicationSupport.appending(path: "DownloadsButler", directoryHint: .isDirectory)

        if !fileManager.fileExists(atPath: current.path),
           fileManager.fileExists(atPath: legacy.path) {
            do {
                try fileManager.moveItem(at: legacy, to: current)
            } catch {
                return legacy
            }
        }

        try? fileManager.createDirectory(at: current, withIntermediateDirectories: true)
        return current
    }

    static func hasManagedMarker(in folder: URL, fileManager: FileManager = .default) -> Bool {
        [managedMarkerName, legacyManagedMarkerName].contains { markerName in
            fileManager.fileExists(atPath: folder.appending(path: markerName).path)
        }
    }
}
