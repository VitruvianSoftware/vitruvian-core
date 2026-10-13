// swift-tools-version: 5.9
// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import PackageDescription

let package = Package(
    name: "HomeSpeaker",
    platforms: [.macOS(.v14)],
    products: [
        // The tool for the Vitruvian app; the app itself is the executable
        // target below, built by `swift build` as before.
        .executable(name: "homespeaker-tool", targets: ["HomeSpeakerTool"]),
    ],
    dependencies: [
        // The Vitruvian tool kit, for the tool targets below. The kit's
        // `ToolWaker` came with 1.1.0 (`tool/version_test.py` holds this
        // line to it).
        .package(url: "https://github.com/VitruvianSoftware/vitruvian-sdk", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "HomeSpeakerCore",
            path: "Sources/HomeSpeakerCore"
        ),
        .executableTarget(
            name: "HomeSpeaker",
            dependencies: ["HomeSpeakerCore"],
            path: "Sources/HomeSpeaker"
        ),
        // The HomeSpeaker tool for the Vitruvian app: its core, its
        // program and its tests. MUST MIRROR BUILD, target for target.
        .target(
            name: "HomeSpeakerToolCore",
            dependencies: [
                "HomeSpeakerCore",
                .product(name: "VitruvianToolKit", package: "vitruvian-sdk"),
                .product(name: "VitruvianToolProtocol", package: "vitruvian-sdk"),
            ],
            path: "Sources/HomeSpeakerToolCore"
        ),
        .executableTarget(
            name: "HomeSpeakerTool",
            dependencies: ["HomeSpeakerToolCore"],
            path: "Sources/HomeSpeakerTool"
        ),
        .testTarget(
            name: "HomeSpeakerToolTests",
            dependencies: ["HomeSpeakerCore", "HomeSpeakerToolCore"],
            path: "Tests/HomeSpeakerToolTests"
        ),
        .testTarget(
            name: "HomeSpeakerTests",
            dependencies: ["HomeSpeakerCore"],
            path: "Tests/HomeSpeakerTests"
        ),
    ]
)
