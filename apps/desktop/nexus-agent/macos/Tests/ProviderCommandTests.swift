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

/// A provider can be a command the user wrote, with `{prompt}` and `{model}`
/// standing for the prompt and the model. These are the rules for turning
/// one into a program and its arguments, for choosing how a provider is run,
/// and for reading what a command printed. The standalone app's own chat,
/// removed in step 3c (`QuickPromptWindow.swift`; see git history before
/// `b14d76b54`), was the specification, and "the standalone" below means
/// that chat as it was; where the shared code departs from it, the test
/// says so.
final class ProviderCommandTests: XCTestCase {

    private func command(_ template: String, prompt: String = "hello", model: String = "m1")
        -> (executable: String, arguments: [String])? {
        NexusAgentSupport.providerCommand(template: template, prompt: prompt, model: model)
    }

    private func assertCommand(_ template: String, prompt: String = "hello", model: String = "m1",
                               runs executable: String, _ arguments: [String],
                               _ message: String = "", line: UInt = #line) {
        let parsed = command(template, prompt: prompt, model: model)
        XCTAssertEqual(parsed?.executable, executable, message, line: line)
        XCTAssertEqual(parsed?.arguments, arguments, message, line: line)
    }

    // MARK: - A template becomes a program and its arguments

    func testATemplateIsSplitOnSpacesAndItsPlaceholdersFilledIn() {
        assertCommand("mytool --fast", runs: "mytool", ["--fast"], "no placeholders")
        assertCommand("mytool", runs: "mytool", [], "a program alone")
        assertCommand("mytool {prompt}", runs: "mytool", ["hello"], "the prompt alone")
        assertCommand("mytool --model {model} -p {prompt}", runs: "mytool", ["--model", "m1", "-p", "hello"])
        assertCommand("mytool --ask={prompt} --with={model}", runs: "mytool", ["--ask=hello", "--with=m1"],
                      "a placeholder inside a longer word")
        assertCommand("mytool {prompt} {prompt}", runs: "mytool", ["hello", "hello"], "every occurrence is filled")
        assertCommand("  mytool   {prompt}  ", runs: "mytool", ["hello"], "extra spaces make no empty arguments")
    }

    func testQuotesKeepSpacesTogetherAndAreRemoved() {
        assertCommand("mytool \"two words\" 'three more words'", runs: "mytool", ["two words", "three more words"])
        assertCommand("mytool \"{prompt}\"", runs: "mytool", ["hello"], "the prompt inside quotes")
        assertCommand("mytool '{prompt}'", runs: "mytool", ["hello"])
        assertCommand("mytool \"Answer briefly: {prompt}\"", runs: "mytool", ["Answer briefly: hello"])
        assertCommand("mytool \"it's\" 'say \"hi\"'", runs: "mytool", ["it's", "say \"hi\""],
                      "one kind of quote is plain text inside the other")
        assertCommand("mytool pre\"a b\"post", runs: "mytool", ["prea bpost"], "quoted and bare text join into one word")
        assertCommand("\"/Applications/My Tool/run\" {prompt}", runs: "/Applications/My Tool/run", ["hello"],
                      "the program can be quoted too")
    }

    /// The standalone's parser is small, and these are its edges. Each is
    /// kept, because a template a user already saved must go on meaning
    /// what it meant.
    func testTheParsersOdditiesAreTheStandalones() {
        XCTAssertNil(command(""), "an empty template is not a command")
        XCTAssertNil(command("    "), "nor is one of spaces")
        XCTAssertNil(command("\"\""), "empty quotes make no word at all")
        assertCommand("mytool \"\" x", runs: "mytool", ["x"], "so an empty argument cannot be written")
        assertCommand("mytool \"never closed {prompt}", runs: "mytool", ["never closed hello"],
                      "a quote left open runs to the end")
        assertCommand("mytool a\tb", runs: "mytool", ["a\tb"], "only a space separates words, a tab does not")
        assertCommand("mytool a\\ b", runs: "mytool", ["a\\", "b"], "a backslash escapes nothing")
        assertCommand("{model} run {prompt}", runs: "m1", ["run", "hello"],
                      "{model} in the program's own name is filled in like any other word ({prompt} there is refused, below)")
    }

    /// A deliberate departure from the standalone, which fills `{prompt}`
    /// into the program's name like any other word. That is never useful and
    /// is the one way a prompt could choose what gets run, so here a
    /// template whose first word holds `{prompt}` has no program at all.
    /// `{model}` there stays, because the model is the user's own setting.
    func testAPromptCanNeverChooseTheProgram() {
        for template in ["{prompt} x", "{prompt}", "tool{prompt}", "{prompt}tool y {prompt}", "\"{prompt}\" x",
                         "'a {prompt}' x", "{{prompt}model} x", "{model}{prompt} x"] {
            let parsed = command(template, prompt: "rm")
            XCTAssertEqual(parsed?.executable, "", "no program for \(template.debugDescription)")
        }
        // The rest of the line is still cut and filled as always.
        XCTAssertEqual(command("{prompt} x {prompt}", prompt: "rm")?.arguments, ["x", "rm"])
        // The prompt anywhere after the first word is as before, and so is a model in the first word.
        assertCommand("mytool {prompt}", prompt: "rm", runs: "mytool", ["rm"])
        assertCommand("mytool{model} {prompt}", runs: "mytoolm1", ["hello"])
        assertCommand("{model}", runs: "m1", [])
        // A prompt that merely mentions the mark does not make the program's name wrong.
        assertCommand("mytool {prompt}", prompt: "{prompt}", runs: "mytool", ["{prompt}"])
    }

    func testAnEmptyModelBecomesTheStandalonesFixedOne() {
        XCTAssertEqual(NexusAgentSupport.templateFallbackModel, "gemma4:31b-cloud")
        assertCommand("mytool --model {model} {prompt}", model: "",
                      runs: "mytool", ["--model", "gemma4:31b-cloud", "hello"])
        // Only an empty model: one of spaces is passed as it is, as the standalone passes it.
        assertCommand("mytool --model {model}", model: " ", runs: "mytool", ["--model", " "])
    }

    // MARK: - The prompt is one argument, whatever is in it

    /// Review focus 2 of the plan. The template is split into words first
    /// and the prompt is put into its word afterwards, so nothing in a
    /// prompt can start a new argument, close a quote or run a command.
    func testAPromptArrivesAsOneArgumentUnchanged() {
        let prompts = [
            "two words",
            "several   spaced    words ",
            "say \"hi\" and 'bye'",
            "\" --dangerous \"",
            "' ; rm -rf x ; '",
            "a; touch /tmp/owned",
            "$(rm -rf x)",
            "`rm -rf x`",
            "a && b || c | d > e < f",
            "line one\nline two\n",
            "tab\there",
            "back\\slash \\\" \\n",
            "--help",
            "-p --model other",
            "what does {model} mean?",
            "{prompt} {prompt}",
            "{model}{prompt}{model}",
            "~ * ? [a-z] $HOME ${PATH} !! #",
            "émoji 🙂 and ユニコード",
            "",
        ]
        let templates: [(template: String, before: [String], prefix: String, suffix: String, after: [String])] = [
            ("mytool -p {prompt} --model {model}", ["-p"], "", "", ["--model", "m1"]),
            ("mytool -p \"{prompt}\" --model {model}", ["-p"], "", "", ["--model", "m1"]),
            ("mytool -p '{prompt}' --model {model}", ["-p"], "", "", ["--model", "m1"]),
            ("mytool --ask={prompt}", [], "--ask=", "", []),
            ("mytool \"Q: {prompt} (briefly)\" end", [], "Q: ", " (briefly)", ["end"]),
        ]
        for prompt in prompts {
            for entry in templates {
                let parsed = command(entry.template, prompt: prompt)
                XCTAssertEqual(parsed?.executable, "mytool", "prompt \(prompt.debugDescription) in \(entry.template)")
                XCTAssertEqual(parsed?.arguments, entry.before + [entry.prefix + prompt + entry.suffix] + entry.after,
                               "prompt \(prompt.debugDescription) in \(entry.template)")
            }
        }
    }

    /// The one place the shared code does NOT do what the standalone does.
    /// The standalone fills in `{prompt}` and then looks for `{model}` in
    /// the result, so a prompt that mentions `{model}` has those letters
    /// swapped for the model's name. Here each placeholder of the TEMPLATE
    /// is filled once and what was put in is never read again.
    func testWhatIsFilledInIsNeverReadAgain() {
        assertCommand("mytool {prompt} {model}", prompt: "explain {model} to me", model: "m1",
                      runs: "mytool", ["explain {model} to me", "m1"],
                      "the standalone would pass \"explain m1 to me\"")
        assertCommand("mytool {model} {prompt}", prompt: "hi", model: "{prompt}",
                      runs: "mytool", ["{prompt}", "hi"], "a model's name is not read again either")
        assertCommand("mytool {{prompt}model}", prompt: "", model: "m1",
                      runs: "mytool", ["{model}"], "nor can the two join into a placeholder")
    }

    /// For the templates the app ships and a plain one-word prompt, the
    /// arguments are the ones the standalone's parser gave. Worked out by
    /// hand from `parseProviderTemplate` in the removed
    /// `QuickPromptWindow.swift` (git history before `b14d76b54`).
    func testOrdinaryTemplatesGiveWhatTheStandaloneGives() {
        assertCommand(NexusAgentCLIProvider.antigravity.commandTemplate, runs: "agy",
                      ["-p", "hello", "--output-format", "stream-json", "--dangerously-skip-permissions"])
        assertCommand(NexusAgentCLIProvider.claude.commandTemplate, runs: "claude", ["-p", "hello"])
        assertCommand(NexusAgentCLIProvider.ollama.commandTemplate, model: "qwen3", runs: "ollama",
                      ["launch", "claude", "--model", "qwen3", "--", "-p", "hello"])
        assertCommand("ollama run {model} \"{prompt}\"", model: "", runs: "ollama",
                      ["run", "gemma4:31b-cloud", "hello"])
        assertCommand("llm -m {model} {prompt}", runs: "llm", ["-m", "m1", "hello"])
    }

    // MARK: - How a provider is run

    private func provider(_ template: String, id: UUID = UUID()) -> NexusAgentCLIProvider {
        NexusAgentCLIProvider(id: id, name: "Mine", commandTemplate: template, isBuiltIn: false)
    }

    func testTheBuiltInProvidersRunTheirOwnWay() {
        XCTAssertEqual(NexusAgentCLIProvider.antigravity.route, .antigravity)
        XCTAssertEqual(NexusAgentCLIProvider.claude.route, .claude)
        XCTAssertEqual(NexusAgentCLIProvider.ollama.route, .ollama)
    }

    func testAnOwnProviderIsRunByTheFirstWordOfItsTemplate() {
        XCTAssertEqual(provider("claude -p {prompt}").route, .claude)
        XCTAssertEqual(provider("ollama run {model} {prompt}").route, .ollama)
        XCTAssertEqual(provider("llm {prompt}").route, .custom)
        XCTAssertEqual(provider("agy -p {prompt}").route, .custom,
                       "only the built-in Antigravity provider is run as agy; a copy of it is a plain command")
        XCTAssertEqual(provider("").route, .custom)
        XCTAssertEqual(provider("   claude -p {prompt}").route, .claude, "spaces in front do not count")
        XCTAssertEqual(provider("\tollama run").route, .ollama, "nor does a tab")
        XCTAssertEqual(provider("llm claude {prompt}").route, .custom, "only the first word is looked at")
    }

    /// The standalone tests the END of the first word, not the whole of it,
    /// and does not know about quotes. Kept as it is.
    func testTheFirstWordIsMatchedByItsEnding() {
        XCTAssertEqual(provider("/opt/tools/claude -p {prompt}").route, .claude)
        XCTAssertEqual(provider("/usr/local/bin/ollama run").route, .ollama)
        XCTAssertEqual(provider("notclaude {prompt}").route, .claude, "any word ending in claude")
        XCTAssertEqual(provider("my-ollama {prompt}").route, .ollama)
        XCTAssertEqual(provider("\"claude\" -p {prompt}").route, .custom, "a quoted name ends in a quote")
        XCTAssertEqual(provider("claude-code -p {prompt}").route, .custom)
        XCTAssertEqual(provider("Claude -p {prompt}").route, .custom, "capitals matter")
    }

    /// A built-in provider whose template the user edited is still run by
    /// what it IS: its template is not run. The one exception is the
    /// standalone's own: Claude with a template that starts with ollama
    /// goes through Ollama.
    func testAnEditedBuiltInIsStillRunByWhatItIs() {
        func edited(_ builtIn: NexusAgentCLIProvider, _ template: String) -> NexusAgentCLIProvider {
            var copy = builtIn
            copy.commandTemplate = template
            return copy
        }
        XCTAssertEqual(edited(.antigravity, "llm {prompt}").route, .antigravity)
        XCTAssertEqual(edited(.antigravity, "claude -p {prompt}").route, .antigravity)
        XCTAssertEqual(edited(.antigravity, "ollama run x").route, .antigravity)
        XCTAssertEqual(edited(.claude, "llm {prompt}").route, .claude)
        XCTAssertEqual(edited(.claude, "").route, .claude)
        XCTAssertEqual(edited(.claude, "ollama launch claude").route, .ollama)
        XCTAssertEqual(edited(.ollama, "llm {prompt}").route, .ollama)
        XCTAssertEqual(edited(.ollama, "claude -p {prompt}").route, .ollama, "Ollama wins when both could apply")
        XCTAssertEqual(provider("ollama launch claude").route, .ollama)
    }

    func testTheProgramLookedForFollowsTheRoute() {
        XCTAssertEqual(NexusAgentCLIProvider.antigravity.executableName, "agy")
        XCTAssertEqual(provider("/opt/tools/claude -p {prompt}").executableName, "claude",
                       "the standalone runs `claude` by name here, not the path in the template")
        XCTAssertEqual(provider("my-ollama {prompt}").executableName, "ollama")
    }

    // MARK: - Plan mode

    private let wrapper = "[SYSTEM] You are in PLAN MODE. You MUST follow these rules strictly:\n"
        + "- Do NOT create, edit, modify, or delete any files.\n"
        + "- Do NOT run any shell commands or scripts.\n"
        + "- Do NOT execute any tools that modify the filesystem or environment.\n"
        + "- ONLY explain what you WOULD do, step by step, as a detailed plan.\n"
        + "- Present your plan as a numbered list of actions you would take.\n"
        + "- Wait for explicit user approval before taking any action.\n"
        + "\n"
        + "User request: "

    func testThePlanModeWrapperIsTheStandalonesWordForWord() {
        XCTAssertEqual(NexusAgentSupport.planModePrompt("add a test"), wrapper + "add a test")
        XCTAssertEqual(NexusAgentSupport.planModePrompt("two\nlines"), wrapper + "two\nlines")
    }

    func testPlanModeIsFlagsForAgyAndClaudeAndWordsForOllama() {
        let agy = NexusAgentSupport.agentArguments(prompt: "add a test", configuration: NexusAgentConfiguration(),
                                                   conversationID: nil, planMode: true)
        XCTAssertEqual(Array(agy.prefix(2)), ["-p", "add a test"], "agy is told with a flag, the prompt is untouched")
        XCTAssertTrue(agy.contains("plan"))

        let claude = NexusAgentSupport.agentArguments(
            prompt: "add a test", configuration: NexusAgentConfiguration(activeProvider: .claude),
            conversationID: nil, planMode: true)
        XCTAssertEqual(Array(claude.prefix(2)), ["-p", "add a test"])

        let ollama = NexusAgentSupport.agentArguments(
            prompt: "add a test", configuration: NexusAgentConfiguration(model: "m1", activeProvider: .ollama),
            conversationID: nil, planMode: true)
        XCTAssertEqual(Array(ollama.prefix(7)), ["launch", "claude", "--model", "m1", "--", "-p", wrapper + "add a test"])
        XCTAssertTrue(ollama.contains("--permission-mode"), "the flags it already passed are still passed")

        let ollamaOff = NexusAgentSupport.agentArguments(
            prompt: "add a test", configuration: NexusAgentConfiguration(model: "m1", activeProvider: .ollama),
            conversationID: nil, planMode: false)
        XCTAssertEqual(ollamaOff[6], "add a test")
    }

    func testAnOwnProviderRunThroughClaudeOrOllamaGetsThatProvidersArguments() {
        let throughClaude = NexusAgentSupport.agentArguments(
            prompt: "hi", configuration: NexusAgentConfiguration(activeProvider: provider("claude -p {prompt}")),
            conversationID: "c1")
        XCTAssertEqual(throughClaude, NexusAgentSupport.agentArguments(
            prompt: "hi", configuration: NexusAgentConfiguration(activeProvider: .claude), conversationID: "c1"))

        let throughOllama = NexusAgentSupport.agentArguments(
            prompt: "hi", configuration: NexusAgentConfiguration(activeProvider: provider("ollama run {model}")),
            conversationID: nil, ollamaDefaultModel: "llama3.2:latest")
        XCTAssertEqual(Array(throughOllama.prefix(5)), ["launch", "claude", "--model", "llama3.2:latest", "--"])
    }

    // MARK: - The command's surroundings

    func testACommandIsGivenTheStandalonesPath() {
        let present: Set<String> = ["/opt/homebrew/bin", "/usr/bin", "/bin"]
        let environment = NexusAgentSupport.commandEnvironment(
            base: ["PATH": "/custom/bin:/usr/bin", "HOME": "/Users/rig", "NO_COLOR": "0"],
            fileExists: { present.contains($0) })
        XCTAssertEqual(environment["PATH"], "/opt/homebrew/bin:/usr/bin:/bin:/custom/bin:/usr/bin",
                       "the install folders that exist, in their order, then the app's own PATH as it was")
        XCTAssertEqual(environment["NO_COLOR"], "1")
        XCTAssertEqual(environment["HOME"], "/Users/rig", "the rest is the app's own")

        let bare = NexusAgentSupport.commandEnvironment(base: [:], fileExists: { _ in false })
        XCTAssertEqual(bare["PATH"], "/usr/bin:/bin", "with no PATH at all, the standalone's short one")
    }

    // MARK: - What a command printed

    private func outcome(_ output: String, errors: String = "", status: Int32) -> NexusAgentCommandOutcome {
        NexusAgentSupport.commandOutcome(output: Data(output.utf8), errors: Data(errors.utf8), status: status)
    }

    func testWhatACommandPrintsIsTheReply() {
        XCTAssertEqual(outcome("The answer.\n", status: 0), .reply("The answer."))
        XCTAssertEqual(outcome("\n\n  two\nlines  \n", status: 0), .reply("two\nlines"),
                       "space and empty lines around it are cut, inside it they stay")
        XCTAssertEqual(outcome("an answer", errors: "a warning", status: 0), .reply("an answer"),
                       "what it complained about is not shown beside an answer")
        XCTAssertEqual(outcome("partial answer", errors: "then it broke", status: 3), .reply("partial answer"),
                       "an answer is shown even if the command then failed, as the standalone shows it")
    }

    func testACommandThatFailsWithNothingPrintedIsAFailure() {
        XCTAssertEqual(outcome("", errors: "  model not found\n", status: 1),
                       .failed(status: 1, errors: "model not found"))
        XCTAssertEqual(outcome("  \n", status: 127), .failed(status: 127, errors: ""))
        let long = String(repeating: "x", count: 400)
        XCTAssertEqual(outcome("", errors: long, status: 2),
                       .failed(status: 2, errors: String(repeating: "x", count: 300)),
                       "a long complaint is cut to its first 300 characters")
    }

    func testACommandThatPrintsNothingAndSucceedsSaidNothing() {
        XCTAssertEqual(outcome("", status: 0), .noOutput)
        XCTAssertEqual(outcome(" \n", errors: "only a warning", status: 0), .noOutput)
    }

    func testACommandEndedByASignalWasStopped() {
        XCTAssertEqual(outcome("", status: 15), .stopped)
        XCTAssertEqual(outcome("half an answer", status: 9), .stopped)
    }

    func testOutputThatIsNotTextCountsAsNone() {
        let notText = Data([0xFF, 0xFE, 0xFD])
        XCTAssertEqual(NexusAgentSupport.commandOutcome(output: notText, errors: Data(), status: 0), .noOutput)
        XCTAssertEqual(NexusAgentSupport.commandOutcome(output: Data(), errors: notText, status: 4),
                       .failed(status: 4, errors: ""))
    }

    // MARK: - Words

    func testTheWordsForACommandThatCannotRunAreTheStandalones() {
        let strings = NexusAgentHostStrings()
        XCTAssertEqual(strings.invalidCommandTemplate("  "), "Invalid command template:   ")
        XCTAssertEqual(strings.commandNotFound("llm"), "Could not find 'llm' in PATH. Is it installed?")
        XCTAssertEqual(strings.commandExited(status: 3), "Process exited with code 3")
        XCTAssertEqual(strings.commandNoOutput, "No output from provider")
    }
}
