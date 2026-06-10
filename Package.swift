// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NudgeAI",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NudgeAI",
            path: "Sources/NudgeAI"
        ),
        .testTarget(
            name: "NudgeAITests",
            dependencies: ["NudgeAI"],
            path: "Tests/NudgeAITests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
