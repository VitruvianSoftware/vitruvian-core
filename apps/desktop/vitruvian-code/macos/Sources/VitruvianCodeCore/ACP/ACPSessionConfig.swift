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

import Foundation

/// Pure state and fallback planner for ACP session configuration options and legacy session modes,
/// ported from `sessionConfig.ts:1-144` and `AcpSessionRuntime.ts:2675-2698`.
public struct ACPSessionConfigState: Equatable, Sendable {
    /// Synthetic IDs matching T3 Code (`sessionConfig.ts:6-7`).
    public static let sessionModeOptionID = "_t3/session-mode"
    public static let emptyOptionValue = "_t3/empty"

    public enum UpdateAction: Equatable, Sendable {
        case setConfigOption(configId: String, value: ACPConfigOptionValue)
        case setMode(modeId: String)
    }

    public enum ConfigError: Error, Equatable, Sendable, LocalizedError {
        case unsupportedOption(String)
        case invalidValueType(optionID: String)
        case unknownOptionValue(optionID: String, value: String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedOption(let id):
                return "Session config option '\(id)' is not supported by this agent."
            case .invalidValueType(let id):
                return "Invalid value type for session config option '\(id)'."
            case .unknownOptionValue(let id, let value):
                return "Unsupported value '\(value)' for session config option '\(id)'."
            }
        }
    }

    public private(set) var configOptions: [ACPSessionConfigOption]
    public private(set) var modeState: ACPSessionModeState?

    public init(
        configOptions: [ACPSessionConfigOption] = [],
        modeState: ACPSessionModeState? = nil
    ) {
        self.configOptions = configOptions
        self.modeState = Self.deriveModeState(configOptions: configOptions, explicitModes: modeState)
    }

    public init(setupResult: ACPSessionSetupResult) {
        let options = setupResult.configOptions ?? []
        self.configOptions = options
        self.modeState = Self.deriveModeState(configOptions: options, explicitModes: setupResult.modes)
    }

    /// True when the agent reported typed `configOptions` (`sessionConfig.ts:110-141`).
    public var hasConfigOptions: Bool {
        !configOptions.isEmpty
    }

    /// Replaces the tracked `configOptions` list (e.g. after `config_option_update` or `set_config_option`).
    public mutating func applyConfigOptions(_ updated: [ACPSessionConfigOption]) {
        self.configOptions = updated
        if let derived = Self.modeStateFromConfigOptions(updated) {
            self.modeState = derived
        }
    }

    /// Applies `current_mode_update` to the tracked legacy mode state and any mode `configOption`.
    public mutating func applyCurrentModeUpdate(_ currentModeId: String) {
        let trimmed = currentModeId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if var state = modeState, state.availableModes.contains(where: { $0.id == trimmed }) {
            state.currentModeId = trimmed
            modeState = state
        }
        for idx in configOptions.indices
        where configOptions[idx].category == "mode" && configOptions[idx].type == "select" {
            if configOptions[idx].flattenedSelectOptions.contains(where: { $0.value == trimmed }) {
                configOptions[idx].currentValue = .string(trimmed)
            }
        }
    }

    /// Projects the current state into Core's `[AgentConfigOption]` list (`sessionConfig.ts:110-141`).
    public var agentConfigOptions: [AgentConfigOption] {
        if !configOptions.isEmpty {
            return configOptions.compactMap(Self.mapConfigOption)
        }
        guard let modeState, !modeState.availableModes.isEmpty else {
            return []
        }
        return [
            AgentConfigOption(
                id: Self.sessionModeOptionID,
                name: "Mode",
                value: .string(modeState.currentModeId),
                options: modeState.availableModes.map(\.id)
            ),
        ]
    }

    /// Chooses `session/set_config_option` when the agent advertises `configOptions`, falling back
    /// to `session/set_mode` ONLY for the mode option when the agent has no `configOptions`
    /// (`AcpSessionRuntime.ts:2680-2690`, `sessionConfig.ts:110-141`).
    public func planUpdate(id: String, value: AgentConfigValue) throws -> UpdateAction {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let isModeAlias = trimmedID == Self.sessionModeOptionID || trimmedID == "mode"

        if !configOptions.isEmpty {
            let targetOption: ACPSessionConfigOption?
            if let exact = configOptions.first(where: { $0.id == trimmedID }) {
                targetOption = exact
            } else if isModeAlias {
                targetOption = configOptions.first(where: { $0.category == "mode" && $0.type == "select" })
            } else {
                targetOption = nil
            }

            guard let option = targetOption else {
                throw ConfigError.unsupportedOption(trimmedID)
            }

            switch (option.type, value) {
            case ("boolean", .bool(let b)):
                return .setConfigOption(configId: option.id, value: .bool(b))
            case ("select", .string(let s)):
                let allowed = option.flattenedSelectOptions
                if !allowed.isEmpty && !allowed.contains(where: { $0.value == s }) {
                    throw ConfigError.unknownOptionValue(optionID: option.id, value: s)
                }
                return .setConfigOption(configId: option.id, value: .string(s))
            default:
                throw ConfigError.invalidValueType(optionID: option.id)
            }
        }

        // Legacy fallback: only the mode option may use `session/set_mode` (`sessionConfig.ts`).
        guard isModeAlias, let modeState else {
            throw ConfigError.unsupportedOption(trimmedID)
        }
        guard case .string(let nextModeID) = value else {
            throw ConfigError.invalidValueType(optionID: trimmedID)
        }
        if !modeState.availableModes.isEmpty && !modeState.availableModes.contains(where: { $0.id == nextModeID }) {
            throw ConfigError.unknownOptionValue(optionID: trimmedID, value: nextModeID)
        }
        return .setMode(modeId: nextModeID)
    }

    // MARK: - Private Mapping Helpers

    private static func mapConfigOption(_ option: ACPSessionConfigOption) -> AgentConfigOption? {
        switch option.type {
        case "boolean":
            guard case .bool(let flag) = option.currentValue else { return nil }
            return AgentConfigOption(
                id: option.id,
                name: option.name,
                value: .bool(flag),
                options: []
            )
        case "select":
            guard case .string(let current) = option.currentValue else { return nil }
            return AgentConfigOption(
                id: option.id,
                name: option.name,
                value: .string(current),
                options: option.flattenedSelectOptions.map(\.value)
            )
        default:
            return nil
        }
    }

    private static func deriveModeState(
        configOptions: [ACPSessionConfigOption],
        explicitModes: ACPSessionModeState?
    ) -> ACPSessionModeState? {
        if let fromConfig = modeStateFromConfigOptions(configOptions) {
            return fromConfig
        }
        guard let explicitModes,
              !explicitModes.currentModeId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !explicitModes.availableModes.isEmpty else {
            return nil
        }
        return explicitModes
    }

    private static func modeStateFromConfigOptions(
        _ configOptions: [ACPSessionConfigOption]
    ) -> ACPSessionModeState? {
        guard let modeOption = configOptions.first(where: { $0.category == "mode" && $0.type == "select" }),
              case .string(let current) = modeOption.currentValue,
              !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let available = modeOption.flattenedSelectOptions.map { item in
            ACPSessionMode(id: item.value, name: item.name, description: item.description)
        }
        guard !available.isEmpty else { return nil }
        return ACPSessionModeState(currentModeId: current, availableModes: available)
    }
}
