// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices

/// The capability broker against services that record what they were asked
/// and do nothing.
@MainActor
enum ToolBrokerTests {
    static func run(_ suite: TestSuite) {
        checks(suite)
    }

    /// What the broker is told about the world, and what it reported.
    final class World {
        var installed = true
        var granted: Set<AppPermission> = Set(AppPermission.allCases)
        var allowed = true
        var undeclared: [Capability] = []
    }

    static func manifest(_ capabilities: [Capability]) -> ToolManifest {
        ToolManifest(tool: ToolDescriptor(id: ToolID("portManager")!, name: "portManager", symbol: "network",
                                          commands: [])!,
                     group: .tools,
                     capabilities: capabilities.map { CapabilityRequest($0, reason: "test")! },
                     preferences: [], activation: [.onShown], enabledBy: nil)!
    }

    static func checks(_ suite: TestSuite) {
        let world = World()
        let broker = CapabilityBroker(environment: .init(
            isInstalled: { _ in world.installed },
            isGranted: { world.granted.contains($0) },
            allows: { _, _ in world.allowed },
            reportUndeclared: { _, capability in world.undeclared.append(capability) }))
        let tool = manifest([.open])

        suite.expect(broker.refusal(of: .open, for: tool) == nil,
                     "a declared capability of an installed tool is allowed")
        suite.expect(broker.refusal(of: .processes, for: tool) == .notDeclared(.processes)
                         && world.undeclared == [.processes],
                     "a capability the manifest does not list is refused, and reported as a mistake")
        world.installed = false
        suite.expect(broker.refusal(of: .open, for: tool) == .notInstalled,
                     "a tool removed in the hub is refused")
        suite.expect(broker.refusal(of: .processes, for: tool) == .notDeclared(.processes),
                     "not declared is said before not installed")
        world.installed = true
        world.allowed = false
        suite.expect(broker.refusal(of: .open, for: tool) == .unavailable,
                     "a capability the person has not allowed is refused")
    }
}
