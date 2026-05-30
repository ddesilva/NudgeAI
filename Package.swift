// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Cue",
            path: "Sources/Cue"
        )
    ],
    swiftLanguageModes: [.v5]
)
