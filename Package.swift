// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NudgeAI",
    platforms: [.macOS(.v14)],
    dependencies: [
        // SwiftTerm's release tags are sparse; `from: "1.0.0"` resolves to
        // whatever the latest 1.x is at build time.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NudgeAI",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
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
