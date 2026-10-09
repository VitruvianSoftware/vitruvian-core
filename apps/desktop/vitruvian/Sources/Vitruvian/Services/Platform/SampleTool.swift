// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianDesign

/// A tool that is in none of the app's fixed lists, for checking by hand
/// that a surface shows and runs one. `main.swift` registers it only in a
/// build made with `--define=vitruvian_sample_tool=true`; a release build
/// never does, which is why its two strings are plain English.
@MainActor
package enum SampleTool {
    package static let id = ToolID("dev.vitruvian.sample")!
    package static let hello = CommandID(tool: id, name: "hello")!

    /// Safe to call again: a sample already there is left alone. `say` is
    /// what running the command does; the app shows it on screen.
    package static func install(into registry: ToolRegistry = .shared,
                                say: @escaping @MainActor (String) -> Void = { message in
                                    QuickToolHUD.show(icon: "hand.wave", message: message)
                                }) {
        guard registry.tool(id) == nil,
              let command = CommandDescriptor(id: hello, title: "Say hello", symbol: "hand.wave",
                                              surfaces: [.radial, .quickPanel, .commandBar]),
              let tool = ToolDescriptor(id: id, name: "Sample tool", symbol: "hand.wave", commands: [command])
        else { return }
        try? registry.register(tool)
        try? registry.setHandler(.init(title: { _ in command.title },
                                       run: { say("Hello from the sample tool") }),
                                 for: hello)
    }
}
