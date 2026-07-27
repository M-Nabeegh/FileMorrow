import AppKit
import Foundation

@MainActor
final class FolderBrandingService {
    private let markerName = ".downloads-butler-managed"

    func brandManagedFolders(downloadsURL: URL, profile: OrganizationProfile) {
        for definition in profile.enabledCategories where definition.category != .needsReview {
            let folder = downloadsURL.appending(path: definition.folderName, directoryHint: .isDirectory)
            let marker = folder.appending(path: markerName)
            guard FileManager.default.fileExists(atPath: marker.path) else { continue }

            let image = folderIcon(
                color: color(named: definition.color),
                symbolName: definition.icon
            )
            NSWorkspace.shared.setIcon(image, forFile: folder.path)
        }
    }

    private func folderIcon(color: NSColor, symbolName: String) -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high

        let folderConfiguration = NSImage.SymbolConfiguration(pointSize: 410, weight: .regular)
            .applying(.init(paletteColors: [color]))
        let folder = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(folderConfiguration)
        folder?.draw(
            in: NSRect(x: 44, y: 36, width: 424, height: 424),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        let badgeRect = NSRect(x: 306, y: 92, width: 126, height: 126)
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        let badgeConfiguration = NSImage.SymbolConfiguration(pointSize: 67, weight: .semibold)
            .applying(.init(paletteColors: [color]))
        let requestedSymbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "tray.full.fill", accessibilityDescription: nil)
        requestedSymbol?
            .withSymbolConfiguration(badgeConfiguration)?
            .draw(
                in: badgeRect.insetBy(dx: 27, dy: 27),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )

        image.isTemplate = false
        return image
    }

    private func color(named value: String) -> NSColor {
        switch value.lowercased() {
        case "red": .systemRed
        case "orange": .systemOrange
        case "yellow": .systemYellow
        case "green": .systemGreen
        case "mint": .systemMint
        case "teal": .systemTeal
        case "cyan": .systemCyan
        case "blue": .systemBlue
        case "purple": .systemPurple
        case "pink": .systemPink
        case "brown": .systemBrown
        case "gray": .systemGray
        default: .systemIndigo
        }
    }
}
