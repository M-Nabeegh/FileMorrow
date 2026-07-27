// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileMorrow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "FileMorrow",
            path: "Sources/FileMorrow"
        ),
        .testTarget(
            name: "FileMorrowTests",
            dependencies: ["FileMorrow"],
            path: "Tests/FileMorrowTests"
        )
    ]
)
