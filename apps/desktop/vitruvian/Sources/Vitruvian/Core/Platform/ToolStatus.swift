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

    /// The statuses that compete for the mark: of the tools whose status
    /// may be drawn, in their order, each that has set one. `statuses` is
    /// every status kept, a switched-off tool's among them; `tools` is what
    /// leaves that one out.
    package static func shown(of tools: [ToolID], statuses: [ToolID: ToolStatus]) -> [(ToolID, ToolStatus)] {
        tools.compactMap { tool in statuses[tool].map { (tool, $0) } }
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

    /// The built-in mark's verdict: none while no repository is watched,
    /// whatever the last one was.
    package static func gitHub(watching repositories: Int, aggregate: Verdict) -> Verdict? {
        repositories > 0 ? aggregate : nil
    }

    /// What a tool's mark says: the tool's name, a colon, and the tool's
    /// words for its status as one short line, or the app's word for the
    /// state when the tool gave none. For VoiceOver and the tooltip.
    /// `toolName` is the tool's name in the person's language.
    package static func words(for status: ToolStatus, toolName: String, language: AppLanguage,
                              strings: ExternalToolStrings) -> String {
        let said = status.text?.text(for: language.rawValue).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let words = said.isEmpty ? strings.mark(status.state) ?? "" : ToolOwnWords.oneLine(said)
        return ToolOwnWords.oneLine(toolName) + colon(in: language) + words
    }

    /// What stands between the tool's name and its words. The app's
    /// strings write a colon the way each language does; this is the same
    /// rule, for a label made of two of the tool's own texts.
    package static func colon(in language: AppLanguage) -> String {
        switch language {
        case .fr: return "\u{00A0}: "
        case .ja, .zhHans, .zhTW, .zhHK: return "："
        default: return ": "
        }
    }

    /// The name of the closed island's one button. The island is a single
    /// element to assistive technology: what it draws at rest is hidden
    /// from it, and the button over it is all VoiceOver reaches. So what a
    /// status mark says is said here, after the button's own name. `status`
    /// is nil, or blank, when the island shows no tool's mark.
    package static func buttonTitle(_ title: String, saying status: String?, language: AppLanguage) -> String {
        let said = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !said.isEmpty else { return title }
        switch language {
        case .ja, .zhHans, .zhTW, .zhHK: return title + "、" + said
        default: return title + ", " + said
        }
    }
}
