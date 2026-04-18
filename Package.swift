// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MemReleaser",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "MemReleaser"
        ),
        .testTarget(
            name: "MemReleaserTests",
            dependencies: ["MemReleaser"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
