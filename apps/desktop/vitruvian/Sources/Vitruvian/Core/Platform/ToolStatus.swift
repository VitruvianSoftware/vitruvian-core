// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianToolProtocol

/// A tool's status, as the app keeps it: the last one the tool set with
/// `ui/status`. There is no value for "none": a tool with no status has
/// none here.
package struct ToolStatus: Equatable, Sendable {
    /// Never `.none`.
    package let state: StatusState
    /// What it means, in the tool's own words, for VoiceOver and the
    /// tooltip.
    package let text: UIText?
    /// An SF Symbol name the tool gave in place of the state's own glyph.
    package let icon: String?

    /// Nil for `.none`, which is no status.
    package init?(state: StatusState, text: UIText?, icon: String?) {
        guard state != .none else { return nil }
        self.state = state
        self.text = text
        self.icon = icon
    }

    /// What a tool asked for, as a status; nil when it asked for none.
    package init?(_ asked: UIStatusParams) {
        self.init(state: asked.state, text: asked.text, icon: asked.icon)
    }
}

/// The one status mark the closed island shows.
package enum RestingMark: Equatable, Sendable {
    /// The built-in GitHub feature's, for what it watches.
    case gitHub(Verdict)
    /// A tool's.
    case tool(ToolID, ToolStatus)
}

/// Which mark the closed island shows. Its wing holds one beside the agent
/// mark, so of the built-in GitHub mark and every tool's status the worst
/// wins.
package enum RestingStatus {
    /// How bad a state is: failure 3, attention 2, busy 1, ok 0. `none` is
    /// no mark and is below all of them.
    package static func severity(_ state: StatusState) -> Int {
        switch state {
        case .failure: return 3
        case .attention: return 2
        case .busy: return 1
        case .ok: return 0
        case .none: return -1
        }
    }

    /// How bad the built-in mark is, on the same scale: red is a failure,
    /// amber is busy, green is ok. Grey is no mark.
    package static func severity(_ verdict: Verdict) -> Int? {
        switch verdict {
        case .red: return 3
        case .amber: return 1
        case .green: return 0
        case .grey: return nil
        }
    }

    /// The mark to draw: the worst of the built-in one and the tools'. On
    /// a tie the built-in wins, then the tool that comes first in `tools`,
    /// which is the order they were added in. `gitHub` is nil when nothing
    /// is watched. Nil when there is nothing to draw.
    package static func winner(gitHub: Verdict?, tools: [(ToolID, ToolStatus)]) -> RestingMark? {
        var best: (mark: RestingMark, severity: Int)?
        if let gitHub, let severity = severity(gitHub) { best = (.gitHub(gitHub), severity) }
        for (tool, status) in tools {
            let severity = severity(status.state)
            if severity > (best?.severity ?? -1) { best = (.tool(tool, status), severity) }
        }
        return best?.mark
    }
}
