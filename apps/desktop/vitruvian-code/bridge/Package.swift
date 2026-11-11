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

// The bridge: the last release of Nexus Agent, whose only job is to install
// Vitruvian Code (docs/superpowers/specs/2026-11-10-vitruvian-code-rename-design.md).
// It depends on nothing of the app's, nor on anything outside the system.
// MUST MIRROR apps/desktop/vitruvian-code/bridge/BUILD.
let package = Package(
    name: "NexusAgentBridge",
    platforms: [.macOS(.v14)],
    products: [
        // The program is called NexusAgent: old installs update by swapping in
        // NexusAgent.app, and macOS runs the executable the bundle names.
        .executable(name: "NexusAgent", targets: ["NexusAgentBridge"]),
    ],
    targets: [
        .target(name: "BridgeCore", path: "Sources/BridgeCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "NexusAgentBridge", dependencies: ["BridgeCore"], path: "Sources/NexusAgentBridge",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"], path: "Tests/BridgeCoreTests",
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
