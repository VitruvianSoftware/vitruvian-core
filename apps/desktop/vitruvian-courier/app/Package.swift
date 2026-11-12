// swift-tools-version: 5.9
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

// Vitruvian Courier.app. MUST MIRROR BUILD, target for target: VitruvianCourierCore (everything the tests need),
// VitruvianCourier (the app, with @main), VitruvianCourierCoreTests, and VitruvianCourierViewTests, which renders the
// app's views (Bazel builds them without App.swift as :VitruvianCourierViews for it, since a test can't link @main;
// SwiftPM tests the executable target).
//
// `swift run VitruvianCourier` needs an engine: set VITRUVIAN_COURIER_ENGINE_PATH to a built vitruvian-courier-engine,
// and VITRUVIAN_COURIER_DATA_DIR to a scratch folder (never your real data). `scripts/test.sh` runs the tests.
let package = Package(
    name: "VitruvianCourier",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "VitruvianCourierCore",
            path: "Sources/VitruvianCourierCore"
        ),
        .executableTarget(
            name: "VitruvianCourier",
            dependencies: ["VitruvianCourierCore"],
            path: "Sources/VitruvianCourier"
        ),
        .testTarget(
            name: "VitruvianCourierCoreTests",
            dependencies: ["VitruvianCourierCore"],
            path: "Tests/VitruvianCourierCoreTests"
        ),
        .testTarget(
            name: "VitruvianCourierViewTests",
            dependencies: ["VitruvianCourier", "VitruvianCourierCore"],
            path: "Tests/VitruvianCourierViewTests"
        ),
    ]
)
