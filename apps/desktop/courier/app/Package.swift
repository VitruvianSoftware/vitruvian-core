// swift-tools-version: 5.9
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

// Courier.app. MUST MIRROR BUILD, target for target: CourierCore (everything the tests need), Courier (the app,
// with @main), CourierCoreTests, and CourierViewTests, which renders the app's views (Bazel builds them without
// App.swift as :CourierViews for it, since a test can't link @main; SwiftPM tests the executable target).
//
// `swift run Courier` needs an engine: set COURIER_ENGINE_PATH to a built courier-engine, and COURIER_DATA_DIR to a
// scratch folder (never your real data). `scripts/test.sh` runs the tests.
let package = Package(
    name: "Courier",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CourierCore",
            path: "Sources/CourierCore"
        ),
        .executableTarget(
            name: "Courier",
            dependencies: ["CourierCore"],
            path: "Sources/Courier"
        ),
        .testTarget(
            name: "CourierCoreTests",
            dependencies: ["CourierCore"],
            path: "Tests/CourierCoreTests"
        ),
        .testTarget(
            name: "CourierViewTests",
            dependencies: ["Courier", "CourierCore"],
            path: "Tests/CourierViewTests"
        ),
    ]
)
