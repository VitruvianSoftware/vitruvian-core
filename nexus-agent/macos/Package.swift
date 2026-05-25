// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NexusAgent",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NexusAgent",
            path: "Sources/NexusAgent"
        ),
    ]
)
