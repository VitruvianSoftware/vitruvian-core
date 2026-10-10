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
        // The shared chat view. Swift 6 mode, as the core.
        // Its resources are BUILD's `shared_ui_resources`, file for file.
        // SwiftPM writes them to NexusAgent_NexusAgentUI.bundle beside the
        // executable; scripts/bundle.sh copies that folder into the app, and
        // NexusAgentMermaidPage looks for it by that name.
        .target(
            name: "NexusAgentUI",
            dependencies: ["NexusAgentCore"],
            path: "Sources/NexusAgentUI",
            resources: [
                .copy("Resources/mermaid.min.js"),
                .copy("Resources/mermaid-LICENSE.txt"),
            ]
        ),
        .executableTarget(
            name: "NexusAgent",
            dependencies: ["NexusAgentCore", "NexusAgentUI"],
            path: "Sources/NexusAgent",
            // The app shell is Swift 5 code. Only the shared core is Swift 6.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The same tests BUILD's NexusAgentTests runs, over the two shared
        // libraries (the app has `@main`, so it cannot be linked into a test). Swift 5 mode
        // because that is how Bazel compiles them. They find the shared
        // sources and `../testdata` from their own file's path, so nothing is
        // copied; `swift build` does not compile this target.
        .testTarget(
            name: "NexusAgentTests",
            dependencies: ["NexusAgentCore", "NexusAgentUI"],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
