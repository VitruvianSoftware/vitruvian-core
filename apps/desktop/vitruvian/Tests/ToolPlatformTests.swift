// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// The tool platform's values and registry, run over doubles: no tool runs.
enum ToolPlatformTests {
    static func run(_ suite: TestSuite) {
        ids(suite)
        descriptors(suite)
    }

    static func ids(_ suite: TestSuite) {
        suite.expect(ToolID("screenshot")?.isBundledForm == true, "a bare name is a bundled tool id")
        suite.expect(ToolID("com.acme.deploys")?.isBundledForm == false, "a dotted name is an outside tool id")
        for bad in ["", ".", ".acme", "acme.", "a/b", "a b", "a\nb", String(repeating: "a", count: 129)] {
            suite.expect(ToolID(bad) == nil, "\(bad.debugDescription) is not a tool id")
        }

        let parsed = CommandID("screenshot/capture")
        suite.expect(parsed?.tool.rawValue == "screenshot" && parsed?.name == "capture",
                     "a command id splits into its tool and its name")
        suite.expect(parsed?.rawValue == "screenshot/capture", "a command id writes back what it read")
        suite.expect(CommandID("com.acme.deploys/open")?.tool.rawValue == "com.acme.deploys",
                     "an outside tool's command keeps the dotted tool id")
        for bad in ["", "noslash", "a/b/c", "/capture", "screenshot/", "a b/c", "a/b c"] {
            suite.expect(CommandID(bad) == nil, "\(bad.debugDescription) is not a command id")
        }
    }

    static func descriptors(_ suite: TestSuite) {
        let tool = ToolID("screenshot")!
        let capture = CommandDescriptor(id: CommandID(tool: tool, name: "capture")!, title: "Capture",
                                        symbol: "camera.viewfinder", surfaces: [.radial])
        let made = ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder", commands: [capture])
        suite.expect(made?.feature == .screenshot, "a bundled tool finds its feature by id")
        suite.expect(ToolDescriptor(id: ToolID("com.acme.deploys")!, name: "Deploys", symbol: "shippingbox",
                                    commands: [])?.feature == nil,
                     "an outside tool has no feature")

        let stray = CommandDescriptor(id: CommandID("colorPicker/pick")!, title: "Pick", symbol: "eyedropper",
                                      surfaces: [.radial])
        suite.expect(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder",
                                    commands: [stray]) == nil,
                     "a tool cannot declare another tool's command")
        suite.expect(ToolDescriptor(id: tool, name: "Screenshot", symbol: "camera.viewfinder",
                                    commands: [capture, capture]) == nil,
                     "a tool cannot declare one command twice")
    }
}
