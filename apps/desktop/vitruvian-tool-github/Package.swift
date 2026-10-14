// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import PackageDescription

// MUST MIRROR apps/desktop/vitruvian-tool-github/BUILD, target for target.
// The monorepo builds this with Bazel against the kit in packages/vitruvian-sdk;
// the mirror, VitruvianSoftware/vitruvian-tool-github, builds it with
// `swift build` against the published kit, from the version below. A target
// added to BUILD but not here (or the reverse) breaks one of the two in
// silence (see packages/vitruvian-sdk/Package.swift).
let package = Package(
    name: "vitruvian-tool-github",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "github-tool", targets: ["github-tool"]),
    ],
    dependencies: [
        // The kit's `App.status` and a preference's `options` came with
        // 1.3.0 (`version_test.py` holds this line to it).
        .package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "GitHubToolCore",
            dependencies: [
                .product(name: "VitruvianToolKit", package: "vitruvian-sdk"),
                .product(name: "VitruvianToolProtocol", package: "vitruvian-sdk"),
            ],
            path: "Sources/GitHubToolCore"
        ),
        .executableTarget(
            name: "github-tool",
            dependencies: ["GitHubToolCore"],
            path: "Sources/github-tool"
        ),
        .testTarget(
            name: "GitHubToolCoreTests",
            dependencies: ["GitHubToolCore"],
            path: "Tests/GitHubToolCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
