// swift-tools-version: 5.9
// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

// Courier.app. MUST MIRROR BUILD, target for target: CourierCore (everything the tests need), Courier (the app,
// with @main, which no test can link) and CourierCoreTests.
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
    ]
)
