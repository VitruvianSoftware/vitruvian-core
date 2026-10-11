// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

extension ToolRegistry {
    /// Lists a tool that runs as its own program: its name and each
    /// command's title in the person's language, as the tool's author
    /// wrote them, with English where the author wrote no other. Its
    /// commands run through the tool host, like those of a feature that has
    /// become a tool, and "can it run?" is the host's answer.
    package func register(_ tool: ExternalToolManifest, host: @escaping @MainActor () -> ToolHost) throws {
        let descriptor = tool.manifest.tool
        try register(descriptor)
        try setName({ language in tool.name.text(for: language.rawValue) ?? descriptor.name }, for: descriptor.id)
        for command in descriptor.commands {
            let titles = tool.commandTitles[command.id]
            try setHandler(.init(title: { language in titles?.text(for: language.rawValue) ?? command.title },
                                 isRunnable: { host().canRun(command.id) },
                                 run: { host().run(command.id) }),
                           for: command.id)
        }
    }
}
