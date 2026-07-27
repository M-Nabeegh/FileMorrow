// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DownloadsButler",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "DownloadsButler",
            path: "Sources/DownloadsButler"
        ),
        .testTarget(
            name: "DownloadsButlerTests",
            dependencies: ["DownloadsButler"],
            path: "Tests/DownloadsButlerTests"
        )
    ]
)
