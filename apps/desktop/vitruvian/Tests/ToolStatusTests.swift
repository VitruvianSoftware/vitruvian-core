// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// The one status mark the closed island shows: which of the built-in
/// GitHub mark and every tool's status it is. Plain values; nothing is
/// drawn.
enum ToolStatusTests {
    static func run(_ suite: TestSuite) {
        noStatusAndNoGitHubIsNoMark(suite)
        theBuiltInAloneIsTheBuiltIn(suite)
        theWorstWins(suite)
        aTieGoesToTheBuiltInThenTheEarlierTool(suite)
        okIsAMark(suite)
        noneIsNoStatus(suite)
        aSwitchedOffStatusIsKeptAndNotDrawn(suite)
        theBuiltInMarkIsWhatItWas(suite)
        eachStateHasTheBuiltInsLook(suite)
        aToolsIconIsUsedWhenThisMacHasIt(suite)
        theLabelIsTheToolsNameAndItsWords(suite)
        aClickOpensTheToolsPageUnlessItIsOK(suite)
        theIslandsButtonSaysTheMark(suite)
    }

    static let first = ToolID("com.acme.deploys")!
    static let second = ToolID("com.acme.checks")!

    static func status(_ state: StatusState, text: UIText? = nil, icon: String? = nil) -> ToolStatus {
        ToolStatus(state: state, text: text, icon: icon)!
    }

    /// The states that are a mark, mildest first, and the verdicts that
    /// are, the same way.
    static let states: [StatusState] = [.ok, .busy, .attention, .failure]
    static let verdicts: [Verdict] = [.green, .amber, .red]

    static func noStatusAndNoGitHubIsNoMark(_ suite: TestSuite) {
        suite.expect(RestingStatus.winner(gitHub: nil, tools: []) == nil,
                     "with no tool's status and nothing watched on GitHub there is no mark")
    }

    static func theBuiltInAloneIsTheBuiltIn(_ suite: TestSuite) {
        for verdict in verdicts {
            suite.expect(RestingStatus.winner(gitHub: verdict, tools: []) == .gitHub(verdict),
                         "with no tool's status the mark is the built-in one, as it is today (\(verdict))")
        }
        suite.expect(RestingStatus.winner(gitHub: .grey, tools: []) == nil && RestingStatus.severity(Verdict.grey) == nil,
                     "a grey verdict is no mark, as it is today")
        suite.expect(RestingStatus.winner(gitHub: .grey, tools: [(first, status(.ok))]) == .tool(first, status(.ok)),
                     "and a tool's status shows beside a grey built-in, which shows nothing")
    }

    static func theWorstWins(_ suite: TestSuite) {
        suite.expect(states.map { RestingStatus.severity($0) } == [0, 1, 2, 3]
                         && verdicts.map { RestingStatus.severity($0) } == [0, 1, 3],
                     "failure and red are the worst, then attention, then busy and amber, then ok and green")
        for (low, mild) in states.enumerated() {
            for harsh in states[(low + 1)...] {
                let wanted = RestingMark.tool(second, status(harsh))
                suite.expect(RestingStatus.winner(gitHub: nil, tools: [(first, status(mild)), (second, status(harsh))]) == wanted
                                 && RestingStatus.winner(gitHub: nil,
                                                         tools: [(second, status(harsh)), (first, status(mild))]) == wanted,
                             "of two tools the worse status wins, whichever was added first (\(mild), \(harsh))")
            }
        }
        for verdict in verdicts {
            for state in states {
                let built = RestingStatus.severity(verdict) ?? -1
                let tools = RestingStatus.severity(state)
                let got = RestingStatus.winner(gitHub: verdict, tools: [(first, status(state))])
                let wanted: RestingMark = tools > built ? .tool(first, status(state)) : .gitHub(verdict)
                suite.expect(got == wanted,
                             "of the built-in mark and a tool's the worse wins (\(verdict), \(state)): \(String(describing: got))")
            }
        }
    }

    static func aTieGoesToTheBuiltInThenTheEarlierTool(_ suite: TestSuite) {
        suite.expect(RestingStatus.winner(gitHub: .red, tools: [(first, status(.failure))]) == .gitHub(.red)
                         && RestingStatus.winner(gitHub: .amber, tools: [(first, status(.busy))]) == .gitHub(.amber)
                         && RestingStatus.winner(gitHub: .green, tools: [(first, status(.ok))]) == .gitHub(.green),
                     "on a tie the built-in mark wins")
        suite.expect(RestingStatus.winner(gitHub: nil, tools: [(first, status(.busy, text: "one")),
                                                               (second, status(.busy, text: "two"))])
                         == .tool(first, status(.busy, text: "one")),
                     "and of two tools that tie, the one added first")
    }

    static func okIsAMark(_ suite: TestSuite) {
        suite.expect(RestingStatus.winner(gitHub: nil, tools: [(first, status(.ok))]) == .tool(first, status(.ok)),
                     "a tool that says all is well has a mark: the green tick")
    }

    static func noneIsNoStatus(_ suite: TestSuite) {
        suite.expect(ToolStatus(state: .none, text: "gone", icon: "xmark") == nil
                         && ToolStatus(UIStatusParams(state: .none)) == nil,
                     "none is no status: there is no value for it")
        suite.expect(ToolStatus(UIStatusParams(state: .busy, text: "Working", icon: "arrow.triangle.branch"))
                         == status(.busy, text: "Working", icon: "arrow.triangle.branch"),
                     "any other state is kept with its words and its glyph, as the tool sent them")
    }
}

extension ToolStatusTests {
    static let english = FeatureStrings.externalTools(.enUS)

    static func mark(_ status: ToolStatus, name: String = "Deploys", language: AppLanguage = .enUS,
                     hasSymbol: (String) -> Bool = { _ in true }) -> ToolStatusMarkContent {
        ToolStatusMarkContent(status, toolName: name, language: language,
                              strings: FeatureStrings.externalTools(language), hasSymbol: hasSymbol)
    }

    static func aSwitchedOffStatusIsKeptAndNotDrawn(_ suite: TestSuite) {
        let kept: [ToolID: ToolStatus] = [first: status(.failure), second: status(.busy)]
        suite.expect(RestingStatus.winner(gitHub: nil, tools: RestingStatus.shown(of: [first, second], statuses: kept))
                         == .tool(first, status(.failure)),
                     "the statuses that compete are those of the tools whose status is switched on, in their order")
        suite.expect(RestingStatus.winner(gitHub: nil, tools: RestingStatus.shown(of: [second], statuses: kept))
                         == .tool(second, status(.busy))
                         && RestingStatus.winner(gitHub: .green, tools: RestingStatus.shown(of: [], statuses: kept))
                         == .gitHub(.green),
                     "a status the person switched off is kept and not drawn: another tool's shows, or the built-in")
        suite.expect(RestingStatus.shown(of: [first, second], statuses: [:]).isEmpty,
                     "and a tool that has set none has none to draw")
    }

    static func theBuiltInMarkIsWhatItWas(_ suite: TestSuite) {
        suite.expect(NotchGitHubRestingIndicator.verdict(watching: 0, aggregate: .red) == nil
                         && NotchGitHubRestingIndicator.verdict(watching: 0, aggregate: .green) == nil,
                     "with no repository watched the built-in has no verdict, whatever its last one was")
        for verdict in Verdict.allCases {
            suite.expect(NotchGitHubRestingIndicator.verdict(watching: 2, aggregate: verdict) == verdict,
                         "with some watched it is their verdict (\(verdict))")
        }
    }

    static func eachStateHasTheBuiltInsLook(_ suite: TestSuite) {
        typealias Look = ToolStatusMarkContent
        let ok = mark(status(.ok)), busy = mark(status(.busy)), attention = mark(status(.attention))
        let failure = mark(status(.failure))
        suite.expect(ok.symbol == "checkmark" && ok.pointSize == 8 && ok.weight == .bold && ok.tint == .green && !ok.breathes,
                     "ok is the built-in's green: a tick, 8 points, bold, still")
        suite.expect(busy.symbol == "arrow.triangle.2.circlepath" && busy.pointSize == 9 && busy.weight == .medium
                         && busy.tint == .orange && busy.breathes,
                     "busy is the built-in's amber in size and motion: 9 points, medium, orange, breathing")
        suite.expect(attention.symbol == "exclamationmark.circle.fill" && attention.pointSize == 8
                         && attention.weight == .bold && attention.tint == .yellow && !attention.breathes,
                     "attention is yellow: a mark in a circle, 8 points, bold, still")
        suite.expect(failure.symbol == "exclamationmark.triangle.fill" && failure.pointSize == 8
                         && failure.weight == .bold && failure.tint == .red && !failure.breathes,
                     "failure is the built-in's red: a warning triangle, 8 points, bold, still")
        suite.expect(Look.breathingScale == 0.9...1.15 && Look.breathingOpacity == 0.65...1.0 && Look.breathingSeconds == 0.9,
                     "the breathing is the built-in's: scale 0.9 to 1.15, opacity 0.65 to 1, 0.9 seconds each way")
        suite.expect([ok, busy, attention, failure].filter(\.breathes) == [busy], "only busy breathes")
    }

    static func aToolsIconIsUsedWhenThisMacHasIt(_ suite: TestSuite) {
        let branch = status(.busy, icon: "arrow.triangle.branch")
        let own = mark(branch)
        suite.expect(own.symbol == "arrow.triangle.branch" && own.pointSize == 9 && own.weight == .medium
                         && own.tint == .orange && own.breathes,
                     "a tool's own glyph replaces the state's; the colour, the size, the weight and the motion stay the app's")
        suite.expect(mark(branch, hasSymbol: { _ in false }).symbol == "arrow.triangle.2.circlepath",
                     "a glyph this Mac does not have draws the state's own")
        suite.expect(mark(status(.failure, icon: "  ")).symbol == "exclamationmark.triangle.fill"
                         && mark(status(.failure, icon: "")).symbol == "exclamationmark.triangle.fill",
                     "and so does a blank one")
        suite.expect(mark(status(.attention, icon: "hand.raised.fill")).symbol == "hand.raised.fill"
                         && mark(status(.attention, icon: "hand.raised.fill")).tint == .yellow,
                     "for any state")
    }

    static func theLabelIsTheToolsNameAndItsWords(_ suite: TestSuite) {
        suite.expect(mark(status(.failure, text: "main is red on vitruvian-core")).label == "Deploys: main is red on vitruvian-core",
                     "the label is the tool's name, a colon and the tool's words")
        suite.expect(mark(status(.ok)).label == "Deploys: OK" && mark(status(.busy)).label == "Deploys: Working"
                         && mark(status(.attention)).label == "Deploys: Needs attention"
                         && mark(status(.failure)).label == "Deploys: Failed",
                     "with no words from the tool, the app says its own word for the state")
        suite.expect(mark(status(.busy, text: "   ")).label == "Deploys: Working",
                     "words that are only spaces are no words")
        let words = UIText.languages(LocalizedText(["en": "Checks are running", "fr": "Vérifications en cours"]))
        suite.expect(mark(status(.busy, text: words), language: .fr).label == "Deploys\u{00A0}: Vérifications en cours"
                         && mark(status(.busy, text: words), language: .de).label == "Deploys: Checks are running"
                         && mark(status(.busy), language: .fr).label == "Deploys\u{00A0}: En cours",
                     "the words follow the person's language, and so does the app's word and the colon's spacing")
        let long = mark(status(.failure, text: .plain("line one\nline two \u{202E}" + String(repeating: "x", count: 500))),
                        name: "De\nploys" + String(repeating: "y", count: 500))
        let parts = long.label.components(separatedBy: ": ")
        suite.expect(parts.count == 2 && parts[0].count == ToolOwnWords.limit && parts[0].hasPrefix("De ploysyyy")
                         && parts[1].count == ToolOwnWords.limit && parts[1].hasPrefix("line one line two xxx")
                         && parts[1].hasSuffix("…") && !long.label.contains("\n")
                         && !long.label.unicodeScalars.contains("\u{202E}"),
                     "a text of 500 characters with a line break becomes one line of 120, and the name is cut the same way")
    }

    static func aClickOpensTheToolsPageUnlessItIsOK(_ suite: TestSuite) {
        let page = ToolPanelHost.Key(tool: first, panel: "deploys")
        let other = ToolPanelHost.Key(tool: second, panel: "checks")
        for state in [StatusState.busy, .attention, .failure] {
            suite.expect(RestingStatus.opens(.tool(first, status(state)), pages: [other, page]) == page,
                         "a click while a tool's mark says \(state) opens that tool's island page")
        }
        suite.expect(RestingStatus.opens(.tool(first, status(.ok)), pages: [page]) == nil,
                     "a green mark asks for nothing: the click does what it does today")
        suite.expect(RestingStatus.opens(.gitHub(.red), pages: [page]) == nil && RestingStatus.opens(nil, pages: [page]) == nil,
                     "the built-in mark, and no mark, leave the click as it is today")
        suite.expect(RestingStatus.opens(.tool(first, status(.failure)), pages: [other]) == nil
                         && RestingStatus.opens(.tool(first, status(.failure)), pages: []) == nil,
                     "a tool with no island page, or whose page the person hid, leaves it as it is today too")
    }

    /// The closed island is one element to assistive technology: a button
    /// over a drawing it cannot see. So the button's name carries what the
    /// mark says.
    static func theIslandsButtonSaysTheMark(_ suite: TestSuite) {
        let failed = RestingStatus.words(for: status(.failure), toolName: "Deploys", language: .enUS, strings: english)
        suite.expect(failed == "Deploys: Failed" && failed == mark(status(.failure)).label,
                     "what the mark says is one rule, the same for the drawing and for the button")
        suite.expect(RestingStatus.buttonTitle("Open Dynamic Island", saying: failed, language: .enUS)
                         == "Open Dynamic Island, Deploys: Failed",
                     "the closed island's button is named with the mark's words after its own name")
        suite.expect(RestingStatus.buttonTitle("Open Dynamic Island", saying: nil, language: .enUS) == "Open Dynamic Island"
                         && RestingStatus.buttonTitle("Open Dynamic Island", saying: "  ", language: .enUS) == "Open Dynamic Island",
                     "with no mark the button keeps its own name, with nothing after it")
        suite.expect(RestingStatus.buttonTitle("開く", saying: "Deploys：失敗", language: .ja) == "開く、Deploys：失敗",
                     "the pause between the two is written the way the language writes it")
        suite.expect(RestingStatus.gitHub(watching: 0, aggregate: .red) == nil
                         && RestingStatus.gitHub(watching: 1, aggregate: .red) == .red,
                     "the built-in mark's rule is one rule too: no repository watched is no mark")
    }
}
