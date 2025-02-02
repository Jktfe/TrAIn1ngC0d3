// swift-tools-version: 5.9
import PackageDescription

// Remove swift-algorithms dependency
let package = Package(
    name: "TrAIn1ngC0d3",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "TrAIn1ngC0d3",
            targets: ["TrAIn1ngC0d3"]
        )
    ],
    targets: [
        .executableTarget(
            name: "TrAIn1ngC0d3",
            path: "Sources/TrAIn1ngC0d3",
            resources: [.copy("../../Resources")]
        )
    ]
)