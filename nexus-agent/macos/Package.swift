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
    name: "NexusAgent",
    platforms: [.macOS(.v14)],
    targets: [
        // MUST MIRROR nexus-agent/macos/BUILD. These sources have TWO build
        // definitions -- Bazel for the monorepo, SwiftPM for the exported
        // standalone (VitruvianSoftware/nexus-agent) -- and only the Bazel one
        // runs in this repo's CI. When this manifest omitted NexusAgentCore,
        // `bazel build //nexus-agent/macos:NexusAgent` stayed green here while
        // EVERY release build on the mirror failed with
        // "no such module 'NexusAgentCore'", from 2026-07-11 until 2026-08-20.
        // Nothing was watching the mirror, so nothing said so (#1511, #1851).
        // A target added to BUILD must be added here in the same change.
        .target(
            name: "NexusAgentCore",
            path: "Sources/NexusAgentCore"
        ),
        .executableTarget(
            name: "NexusAgent",
            dependencies: ["NexusAgentCore"],
            path: "Sources/NexusAgent"
        ),
    ]
)

// STILL DIVERGENT, deliberately not fixed here: BUILD declares a
// NexusAgent_tests target over Tests/, and this manifest declares none, so
// `swift test` in the standalone repo reports "no tests found" and passes
// vacuously while the same sources ARE tested here under Bazel. Left out of
// this change because it could not be VERIFIED -- XCTest is unavailable in the
// toolchain this was fixed on -- and the mirror's release workflow runs only
// `swift build`, so shipping an unexercised test target would add an untested
// claim to fix an untested claim. Tracked separately.
