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
//
// Shared by the standalone Vitruvian Code app and the Code feature of the
// Vitruvian desktop app. Written for Vitruvian and released under MIT by its
// copyright holder on 2026-10-09 (apps/desktop/vitruvian-atrium/UPSTREAM.md).

import SwiftUI
import VitruvianCodeCore

/// Pure filtering and formatting rules for `AgentSettingsBar`.
public enum AgentSettingsBarLogic: Sendable {
    /// Returns true for permission/session mode options, which must NEVER appear in the settings bar.
    public static func isModeOption(_ option: AgentConfigOption) -> Bool {
        let trimmedID = option.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedID == ACPSessionConfigState.sessionModeOptionID || trimmedID.lowercased() == "mode" {
            return true
        }
        if let category = option.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           category == "mode" {
            return true
        }
        return false
    }

    /// Filters `options` to the ones that offer selectable choices. Mode options are left out
    /// unless `showsModes`: agy's modes belong to the chat's approval picker, but a registry
    /// agent's modes are its own (OpenCode's "build" and "plan"), which T3 Code lets the user
    /// pick with the agent's other options.
    public static func visibleOptions(from options: [AgentConfigOption], showsModes: Bool = false) -> [AgentConfigOption] {
        options.filter { (showsModes || !isModeOption($0)) && !$0.options.isEmpty }
    }

    /// Whether the chat header shows its own model and effort pickers for `route`. A registry
    /// agent takes neither: its model and effort are its own session options, in the settings
    /// row, and the header's pickers changed nothing for it.
    public static func headerShowsModelAndEffort(for route: VitruvianCodeProviderRoute) -> Bool {
        route != .registry
    }

    /// Plain-text display value for an `AgentConfigOption`.
    public static func displayValue(for option: AgentConfigOption) -> String {
        switch option.value {
        case .string(let s):
            return s
        case .bool(let b):
            return b ? "On" : "Off"
        }
    }
}

/// Slim composer-area row offering one compact menu per live non-mode `AgentConfigOption` with choices.
public struct AgentSettingsBar: View {
    public let options: [AgentConfigOption]
    /// Offers the agent's own mode options too (a registry agent's).
    public let showsModes: Bool
    public let isDisabled: Bool
    public let errorMessage: String?
    public let strings: VitruvianCodeChatStrings
    public let onSelect: (String, AgentConfigValue) -> Void

    public init(
        options: [AgentConfigOption],
        showsModes: Bool = false,
        isDisabled: Bool = false,
        errorMessage: String? = nil,
        strings: VitruvianCodeChatStrings,
        onSelect: @escaping (String, AgentConfigValue) -> Void
    ) {
        self.options = options
        self.showsModes = showsModes
        self.isDisabled = isDisabled
        self.errorMessage = errorMessage
        self.strings = strings
        self.onSelect = onSelect
    }

    private var visibleOptions: [AgentConfigOption] {
        AgentSettingsBarLogic.visibleOptions(from: options, showsModes: showsModes)
    }

    public var body: some View {
        if !visibleOptions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(visibleOptions) { option in
                            optionMenu(for: option)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .disabled(isDisabled)
                .opacity(isDisabled ? 0.5 : 1.0)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(strings.agentSettingsBarLabel)

                if let errorMessage, !errorMessage.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                        Text(verbatim: errorMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 14)
                }
            }
            .padding(.top, 4)
        }
    }

    private func optionMenu(for option: AgentConfigOption) -> some View {
        let current = AgentSettingsBarLogic.displayValue(for: option)
        return Menu {
            ForEach(option.options, id: \.self) { choice in
                Button {
                    onSelect(option.id, .string(choice))
                } label: {
                    HStack {
                        Text(verbatim: choice)
                        if case .string(let active) = option.value, active == choice {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            // A native menu label keeps one Text, so name and value are one string.
            HeaderBadgeLabel(isHovered: false) {
                Text(verbatim: "\(option.name)  \(current)")
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("\(option.name): \(current)")
    }
}
