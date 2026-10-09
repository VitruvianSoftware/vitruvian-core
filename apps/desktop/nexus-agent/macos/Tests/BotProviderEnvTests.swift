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

import XCTest

import NexusAgentCore

/// Choosing a provider in an app that manages the bot's program must change
/// what the bot runs; an app that does not must leave the file's lines alone.
final class BotProviderEnvTests: XCTestCase {
    private func value(_ key: String, in content: String) -> String? {
        NexusAgentEnvFile.values(in: content)[key]
    }

    func testWithoutABotProviderTheFilesProviderLinesAreLeftAlone() {
        let existing = "TELEGRAM_BOT_TOKEN=1:a\nCLI_PROVIDER=custom\nCLI_COMMAND_TEMPLATE=ollama run llama3\n"
        let saved = NexusAgentEnvFile.render(NexusAgentConfiguration(botToken: "1:a"), over: existing)
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "custom")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "ollama run llama3")
    }

    func testAntigravityIsWrittenAsAgyWithNoTemplate() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .antigravity
        let existing = "TELEGRAM_BOT_TOKEN=1:a\nCLI_PROVIDER=custom\nCLI_COMMAND_TEMPLATE=ollama run llama3\n"
        let saved = NexusAgentEnvFile.render(configuration, over: existing)
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "agy")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "")
    }

    func testAnyOtherProviderIsWrittenAsCustomWithItsTemplate() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .claude
        let saved = NexusAgentEnvFile.render(configuration, over: "TELEGRAM_BOT_TOKEN=1:a\n")
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "custom")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), NexusAgentCLIProvider.claude.commandTemplate)
    }

    func testANewFileCarriesTheChosenProvider() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .ollama
        let saved = NexusAgentEnvFile.render(configuration, over: nil)
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "custom")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), NexusAgentCLIProvider.ollama.commandTemplate)
        XCTAssertEqual(value("AGY_TIMEOUT_MS", in: saved), "300000")
    }

    func testCommentsAndUnknownKeysSurviveASave() {
        var configuration = NexusAgentConfiguration(botToken: "2:b", model: "m1")
        configuration.botProvider = .antigravity
        let existing = """
        # my notes
        TELEGRAM_BOT_TOKEN=1:a
        AGY_BIN=/opt/agy
        AGY_TIMEOUT_MS=900000
        """
        let saved = NexusAgentEnvFile.render(configuration, over: existing)
        XCTAssertTrue(saved.contains("# my notes"))
        XCTAssertEqual(value("AGY_BIN", in: saved), "/opt/agy")
        XCTAssertEqual(value("AGY_TIMEOUT_MS", in: saved), "900000")
        XCTAssertEqual(value("TELEGRAM_BOT_TOKEN", in: saved), "2:b")
        XCTAssertEqual(value("AGY_MODEL", in: saved), "m1")
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "agy")
    }

    func testATemplateThatDotenvWouldCutIsQuoted() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = NexusAgentCLIProvider(
            id: UUID(), name: "Mine", commandTemplate: "mytool --note a #1 {prompt}", isBuiltIn: false)
        let saved = NexusAgentEnvFile.render(configuration, over: "TELEGRAM_BOT_TOKEN=1:a\n")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "mytool --note a #1 {prompt}")
    }

    func testEveryCopyOfAProviderLineIsRewrittenAndACommentedOneIsLeft() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = .antigravity
        let existing = """
        TELEGRAM_BOT_TOKEN=1:a
        # CLI_PROVIDER=old-note
        CLI_PROVIDER=custom
        CLI_COMMAND_TEMPLATE=one
        AGY_TIMEOUT_MS=900000
        CLI_PROVIDER=custom
        """
        let saved = NexusAgentEnvFile.render(configuration, over: existing)
        let lines = saved.components(separatedBy: .newlines)
        XCTAssertTrue(lines.contains("# CLI_PROVIDER=old-note"))
        XCTAssertFalse(lines.contains("CLI_PROVIDER=custom"))
        XCTAssertEqual(value("CLI_PROVIDER", in: saved), "agy")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "")
    }

    func testATemplateWithAnEqualsSignSurvives() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        configuration.botProvider = NexusAgentCLIProvider(
            id: UUID(), name: "Mine", commandTemplate: "tool --flag=value {prompt}", isBuiltIn: false)
        let saved = NexusAgentEnvFile.render(configuration, over: "TELEGRAM_BOT_TOKEN=1:a\n")
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), "tool --flag=value {prompt}")
    }

    func testATemplateWithAHashAndBothQuoteKindsSurvives() {
        var configuration = NexusAgentConfiguration(botToken: "1:a")
        let template = "tool \"a #1\" 'x'"
        configuration.botProvider = NexusAgentCLIProvider(
            id: UUID(), name: "Mine", commandTemplate: template, isBuiltIn: false)
        let saved = NexusAgentEnvFile.render(configuration, over: "TELEGRAM_BOT_TOKEN=1:a\n")
        // This used to come back cut short: neither single nor double quotes
        // can carry a value that holds both. dotenv also takes backticks, and
        // they can. What still cannot be written is kept, marked lossy, in
        // the examples shared with the bot's tests
        // (apps/desktop/nexus-agent/testdata/env-written-values.json).
        XCTAssertEqual(value("CLI_COMMAND_TEMPLATE", in: saved), template)
    }
}
