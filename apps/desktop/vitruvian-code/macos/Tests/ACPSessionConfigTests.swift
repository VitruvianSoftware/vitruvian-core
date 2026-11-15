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

import Foundation
@testable import VitruvianCodeCore
import XCTest

final class ACPSessionConfigTests: XCTestCase {
    func testWhenConfigOptionsExistUsesSetConfigOptionAndNeverFallsBackToSetMode() throws {
        let setup = ACPSessionSetupResult(
            sessionId: "s1",
            modes: ACPSessionModeState(
                currentModeId: "code",
                availableModes: [
                    ACPSessionMode(id: "code", name: "Code"),
                    ACPSessionMode(id: "plan", name: "Plan"),
                ]
            ),
            configOptions: [
                ACPSessionConfigOption(
                    id: "agent_mode",
                    name: "Mode",
                    category: "mode",
                    type: "select",
                    currentValue: .string("code"),
                    options: [
                        .option(ACPSessionConfigSelectOption(value: "code", name: "Code")),
                        .option(ACPSessionConfigSelectOption(value: "plan", name: "Plan")),
                    ]
                ),
                ACPSessionConfigOption(
                    id: "model",
                    name: "Model",
                    category: "model",
                    type: "select",
                    currentValue: .string("sonnet"),
                    options: [
                        .group(
                            group: "claude",
                            name: "Claude",
                            options: [
                                ACPSessionConfigSelectOption(value: "sonnet", name: "Sonnet"),
                                ACPSessionConfigSelectOption(value: "opus", name: "Opus"),
                            ]
                        ),
                    ]
                ),
                ACPSessionConfigOption(
                    id: "thinking",
                    name: "Extended Thinking",
                    type: "boolean",
                    currentValue: .bool(false)
                ),
            ]
        )

        var state = ACPSessionConfigState(setupResult: setup)
        XCTAssertTrue(state.hasConfigOptions)
        XCTAssertEqual(
            state.agentConfigOptions,
            [
                AgentConfigOption(id: "agent_mode", name: "Mode", value: .string("code"), options: ["code", "plan"]),
                AgentConfigOption(id: "model", name: "Model", value: .string("sonnet"), options: ["sonnet", "opus"]),
                AgentConfigOption(id: "thinking", name: "Extended Thinking", value: .bool(false), options: []),
            ]
        )

        XCTAssertEqual(
            try state.planUpdate(id: "model", value: .string("opus")),
            .setConfigOption(configId: "model", value: .string("opus"))
        )
        XCTAssertEqual(
            try state.planUpdate(id: "thinking", value: .bool(true)),
            .setConfigOption(configId: "thinking", value: .bool(true))
        )
        // Synthetic mode alias resolves to the `category: "mode"` config option via `session/set_config_option`.
        XCTAssertEqual(
            try state.planUpdate(id: ACPSessionConfigState.sessionModeOptionID, value: .string("plan")),
            .setConfigOption(configId: "agent_mode", value: .string("plan"))
        )

        XCTAssertThrowsError(try state.planUpdate(id: "model", value: .string("nonexistent"))) { error in
            XCTAssertEqual(
                error as? ACPSessionConfigState.ConfigError,
                .unknownOptionValue(optionID: "model", value: "nonexistent")
            )
        }
        XCTAssertThrowsError(try state.planUpdate(id: "thinking", value: .string("true"))) { error in
            XCTAssertEqual(
                error as? ACPSessionConfigState.ConfigError,
                .invalidValueType(optionID: "thinking")
            )
        }

        state.applyCurrentModeUpdate("plan")
        XCTAssertEqual(state.agentConfigOptions.first?.value, .string("plan"))
    }

    func testFallbackToSetModeOccursOnlyForModeOptionWhenAgentHasNoConfigOptions() throws {
        let setup = ACPSessionSetupResult(
            sessionId: "s-legacy",
            modes: ACPSessionModeState(
                currentModeId: "ask",
                availableModes: [
                    ACPSessionMode(id: "ask", name: "Ask"),
                    ACPSessionMode(id: "architect", name: "Architect"),
                ]
            ),
            configOptions: nil
        )

        var state = ACPSessionConfigState(setupResult: setup)
        XCTAssertFalse(state.hasConfigOptions)
        XCTAssertEqual(
            state.agentConfigOptions,
            [
                AgentConfigOption(
                    id: ACPSessionConfigState.sessionModeOptionID,
                    name: "Mode",
                    value: .string("ask"),
                    options: ["ask", "architect"]
                ),
            ]
        )

        // Mode option falls back to `session/set_mode`.
        XCTAssertEqual(
            try state.planUpdate(id: ACPSessionConfigState.sessionModeOptionID, value: .string("architect")),
            .setMode(modeId: "architect")
        )
        XCTAssertEqual(
            try state.planUpdate(id: "mode", value: .string("architect")),
            .setMode(modeId: "architect")
        )

        // Non-mode options NEVER fall back to `session/set_mode`.
        XCTAssertThrowsError(try state.planUpdate(id: "model", value: .string("opus"))) { error in
            XCTAssertEqual(
                error as? ACPSessionConfigState.ConfigError,
                .unsupportedOption("model")
            )
        }

        state.applyCurrentModeUpdate("architect")
        XCTAssertEqual(state.agentConfigOptions.first?.value, .string("architect"))
    }
}
