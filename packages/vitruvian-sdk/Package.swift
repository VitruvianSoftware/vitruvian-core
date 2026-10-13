// swift-tools-version: 6.0
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
    name: "VitruvianSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VitruvianToolProtocol", targets: ["VitruvianToolProtocol"]),
        .library(name: "VitruvianToolKit", targets: ["VitruvianToolKit"]),
        .executable(name: "vitruvian-tool", targets: ["VitruvianToolCommandLine"]),
    ],
    targets: [
        // MUST MIRROR packages/vitruvian-sdk/BUILD, target for target. These
        // sources have two build definitions and CI only runs the Bazel one;
        // a target added to BUILD but not here (or the reverse) breaks
        // `swift build` silently (see packages/peripherals/Package.swift).
        //
        // The protocol, as Swift: Foundation only, Swift 6 mode. The Vitruvian
        // desktop app links this module, so it may import nothing of the app.
        .target(
            name: "VitruvianToolProtocol",
            path: "Sources/VitruvianToolProtocol"
        ),
        // What a Swift tool is written with. One thread, Swift 6 mode.
        .target(
            name: "VitruvianToolKit",
            dependencies: ["VitruvianToolProtocol"],
            path: "Sources/VitruvianToolKit"
        ),
        // Everything the `vitruvian-tool` command does, as a library so the
        // tests can link it without the executable's top-level code.
        .target(
            name: "VitruvianToolCLI",
            dependencies: ["VitruvianToolProtocol"],
            path: "Sources/VitruvianToolCLI"
        ),
        .executableTarget(
            name: "VitruvianToolCommandLine",
            dependencies: ["VitruvianToolCLI"],
            path: "Sources/vitruvian-tool"
        ),
        // The samples written in Swift. Their manifests are beside them.
        .executableTarget(
            name: "HelloSwiftSample",
            dependencies: ["VitruvianToolKit"],
            path: "samples/hello-swift",
            exclude: ["vitruvian-tool.json"]
        ),
        .executableTarget(
            name: "HelloPanelSwiftSample",
            dependencies: ["VitruvianToolKit"],
            path: "samples/hello-panel-swift",
            exclude: ["vitruvian-tool.json"]
        ),
        .executableTarget(
            name: "FrontWindowSample",
            dependencies: ["VitruvianToolKit"],
            path: "samples/front-window",
            exclude: ["vitruvian-tool.json"]
        ),
        .testTarget(
            name: "VitruvianToolProtocolTests",
            dependencies: ["VitruvianToolProtocol"],
            path: "Tests/VitruvianToolProtocolTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VitruvianToolCLITests",
            dependencies: ["VitruvianToolCLI", "VitruvianToolProtocol"],
            path: "Tests/VitruvianToolCLITests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "VitruvianToolKitTests",
            dependencies: ["VitruvianToolKit"],
            path: "Tests/VitruvianToolKitTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
