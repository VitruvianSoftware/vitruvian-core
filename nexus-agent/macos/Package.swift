// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GeminiBotBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GeminiBotBar",
            path: "Sources/GeminiBotBar"
        ),
    ]
)
