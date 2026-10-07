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
    name: "Peripherals",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CompXProtocol", targets: ["CompXProtocol"]),
        .library(name: "CompXHID", targets: ["CompXHID"]),
        .library(name: "StatusSignals", targets: ["StatusSignals"]),
        .executable(name: "gravastar-mouse", targets: ["GravaStarMouseTool"]),
    ],
    targets: [
        // MUST MIRROR packages/peripherals/BUILD, target for target. These
        // sources have two build definitions and CI only runs the Bazel one; a
        // target added to BUILD but not here (or the reverse) breaks `swift
        // build` silently (see apps/desktop/nexus-agent/macos/Package.swift).
        .target(
            name: "CompXProtocol",
            path: "Sources/CompXProtocol"
        ),
        .target(
            name: "CompXHID",
            dependencies: ["CompXProtocol"],
            path: "Sources/CompXHID"
        ),
        .target(
            name: "StatusSignals",
            dependencies: ["CompXProtocol", "CompXHID"],
            path: "Sources/StatusSignals"
        ),
        .target(
            name: "GravaStarCLI",
            dependencies: ["CompXProtocol", "CompXHID", "StatusSignals"],
            path: "Sources/GravaStarCLI"
        ),
        .executableTarget(
            name: "GravaStarMouseTool",
            dependencies: ["GravaStarCLI"],
            path: "Sources/gravastar-mouse"
        ),
        .testTarget(
            name: "PeripheralsTests",
            dependencies: ["CompXProtocol", "CompXHID", "StatusSignals", "GravaStarCLI"],
            path: "Tests/PeripheralsTests"
        ),
    ]
)
