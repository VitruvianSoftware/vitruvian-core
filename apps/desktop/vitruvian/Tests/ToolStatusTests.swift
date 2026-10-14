// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianServices
import VitruvianToolProtocol
import VitruvianUI

/// The one status mark the closed island shows: which of every tool's
/// status it is. Plain values; nothing is drawn.
enum ToolStatusTests {
    static func run(_ suite: TestSuite) {
        noStatusIsNoMark(suite)
        theWorstWins(suite)
        aTieGoesToTheEarlierTool(suite)
        okIsAMark(suite)
        noneIsNoStatus(suite)
        aSwitchedOffStatusIsKeptAndNotDrawn(suite)
        eachStateHasItsLook(suite)
        aToolsIconIsUsedWhenThisMacHasIt(suite)
        theLabelIsTheToolsNameAndItsWords(suite)
        aClickOpensTheToolsPageUnlessItIsOK(suite)
        theIslandsButtonSaysTheMark(suite)
        aStatusKeepsItsWords(suite)
        blankWordsAreNoWords(suite)
        theRightWingIsTheAllowanceWithNoWords(suite)
        wordsBeatSeconds(suite)
        secondsCountFromSince(suite)
        aFutureSinceCountsFromZero(suite)
        longWordsAreOneLineOfTwelve(suite)
        nexusOutranksATool(suite)
        theWordsAreTheShownMarks(suite)
        onlySecondsTickEverySecond(suite)
        theButtonSaysTheWordsButNotTheSeconds(suite)
        aMarkWithoutWordsLeavesThePercent(suite)
    }

    static let first = ToolID("com.acme.deploys")!
    static let second = ToolID("com.acme.checks")!

    static func status(_ state: StatusState, text: UIText? = nil, icon: String? = nil, activity: UIText? = nil,
                       since: Date? = nil) -> ToolStatus {
        ToolStatus(state: state, text: text, icon: icon, activity: activity, since: since)!
    }

    /// The states that are a mark, mildest first.
    static let states: [StatusState] = [.ok, .busy, .attention, .failure]

    static func noStatusIsNoMark(_ suite: TestSuite) {
        suite.expect(RestingStatus.winner(tools: []) == nil, "with no tool's status there is no mark")
    }

    static func theWorstWins(_ suite: TestSuite) {
        suite.expect(states.map { RestingStatus.severity($0) } == [0, 1, 2, 3] && RestingStatus.severity(.none) == -1,
                     "failure is the worst, then attention, then busy, then ok; none is below them all")
        for (low, mild) in states.enumerated() {
            for harsh in states[(low + 1)...] {
                let wanted = RestingMark.tool(second, status(harsh))
                suite.expect(RestingStatus.winner(tools: [(first, status(mild)), (second, status(harsh))]) == wanted
                                 && RestingStatus.winner(tools: [(second, status(harsh)), (first, status(mild))]) == wanted,
                             "of two tools the worse status wins, whichever was added first (\(mild), \(harsh))")
            }
        }
    }

    static func aTieGoesToTheEarlierTool(_ suite: TestSuite) {
        for state in states {
            suite.expect(RestingStatus.winner(tools: [(first, status(state, text: "one")),
                                                      (second, status(state, text: "two"))])
                             == .tool(first, status(state, text: "one")),
                         "of two tools that tie, the one added first (\(state))")
        }
    }

    static func okIsAMark(_ suite: TestSuite) {
        suite.expect(RestingStatus.winner(tools: [(first, status(.ok))]) == .tool(first, status(.ok)),
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
        suite.expect(RestingStatus.winner(tools: RestingStatus.shown(of: [first, second], statuses: kept))
                         == .tool(first, status(.failure)),
                     "the statuses that compete are those of the tools whose status is switched on, in their order")
        suite.expect(RestingStatus.winner(tools: RestingStatus.shown(of: [second], statuses: kept))
                         == .tool(second, status(.busy))
                         && RestingStatus.winner(tools: RestingStatus.shown(of: [], statuses: kept)) == nil,
                     "a status the person switched off is kept and not drawn: another tool's shows, or none")
        suite.expect(RestingStatus.shown(of: [first, second], statuses: [:]).isEmpty,
                     "and a tool that has set none has none to draw")
    }

    /// The look is the one the built-in GitHub feature's mark had, number
    /// for number, and stays so now that the feature is gone.
    static func eachStateHasItsLook(_ suite: TestSuite) {
        typealias Look = ToolStatusMarkContent
        let ok = mark(status(.ok)), busy = mark(status(.busy)), attention = mark(status(.attention))
        let failure = mark(status(.failure))
        suite.expect(ok.symbol == "checkmark" && ok.pointSize == 8 && ok.weight == .bold && ok.tint == .green && !ok.breathes,
                     "ok is green: a tick, 8 points, bold, still")
        suite.expect(busy.symbol == "arrow.triangle.2.circlepath" && busy.pointSize == 9 && busy.weight == .medium
                         && busy.tint == .orange && busy.breathes,
                     "busy is amber: 9 points, medium, orange, breathing")
        suite.expect(attention.symbol == "exclamationmark.circle.fill" && attention.pointSize == 8
                         && attention.weight == .bold && attention.tint == .yellow && !attention.breathes,
                     "attention is yellow: a mark in a circle, 8 points, bold, still")
        suite.expect(failure.symbol == "exclamationmark.triangle.fill" && failure.pointSize == 8
                         && failure.weight == .bold && failure.tint == .red && !failure.breathes,
                     "failure is red: a warning triangle, 8 points, bold, still")
        suite.expect(Look.breathingScale == 0.9...1.15 && Look.breathingOpacity == 0.65...1.0 && Look.breathingSeconds == 0.9,
                     "the breathing is scale 0.9 to 1.15, opacity 0.65 to 1, 0.9 seconds each way")
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
            suite.expect(RestingStatus.opens(.tool(first, status(state)), pages: [other, page], nexusRunning: false) == page,
                         "a click while a tool's mark says \(state) opens that tool's island page")
        }
        suite.expect(RestingStatus.opens(.tool(first, status(.ok)), pages: [page], nexusRunning: false) == nil,
                     "a green mark asks for nothing: the click does what it does today")
        suite.expect(RestingStatus.opens(nil, pages: [page], nexusRunning: false) == nil,
                     "no mark leaves the click as it is today")
        suite.expect(RestingStatus.opens(.tool(first, status(.failure)), pages: [other], nexusRunning: false) == nil
                         && RestingStatus.opens(.tool(first, status(.failure)), pages: [], nexusRunning: false) == nil,
                     "a tool with no island page, or whose page the person hid, leaves it as it is today too")
        for state in [StatusState.busy, .attention, .failure] {
            suite.expect(RestingStatus.opens(.tool(first, status(state)), pages: [page], nexusRunning: true) == nil,
                         "while a Nexus session runs the wings show it, so a click opens the Agents page even when a tool says \(state)")
        }
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
    }
}

/// A tool's words on the closed island: what the right-hand wing draws in
/// place of the allowance percent, and what the island's button says.
extension ToolStatusTests {
    static let start = Date(timeIntervalSince1970: 1_760_450_400)

    static func wing(_ status: ToolStatus?, nexusRunning: Bool = false,
                     language: AppLanguage = .enUS) -> RestingStatus.RightWing? {
        RestingStatus.rightWing(status.map { .tool(first, $0) }, nexusRunning: nexusRunning, language: language)
    }

    static func aStatusKeepsItsWords(_ suite: TestSuite) {
        let kept = ToolStatus(UIStatusParams(state: .busy, text: "Checks are running", activity: "3",
                                             since: 1_760_450_400.5))
        suite.expect(kept?.activity == "3" && kept?.since == Date(timeIntervalSince1970: 1_760_450_400.5)
                         && kept?.text == "Checks are running",
                     "a status keeps its words and its start time beside its own words")
        suite.expect(ToolStatus(UIStatusParams(state: .ok))?.activity == nil
                         && ToolStatus(UIStatusParams(state: .ok))?.since == nil,
                     "a status that sends neither has neither")
    }

    static func blankWordsAreNoWords(_ suite: TestSuite) {
        suite.expect(status(.busy, activity: "  ").activity == nil && status(.busy, activity: "\n").activity == nil
                         && ToolStatus(UIStatusParams(state: .busy, activity: " "))?.activity == nil,
                     "words that are only spaces are no words")
    }

    static func theRightWingIsTheAllowanceWithNoWords(_ suite: TestSuite) {
        suite.expect(wing(nil) == .allowance, "with no tool's mark the wing draws the allowance percent, as today")
        suite.expect(wing(status(.failure)) == .allowance
                         && wing(status(.busy, text: "Checks are running", icon: "arrow.triangle.branch")) == .allowance,
                     "a mark without words leaves the percent, whatever its state, its text or its glyph")
    }

    static func wordsBeatSeconds(_ suite: TestSuite) {
        suite.expect(wing(status(.busy, activity: "push", since: start)) == .words("push"),
                     "a status with words and a start time draws the words")
        suite.expect(wing(status(.busy, since: start)) == .seconds(since: start),
                     "a status with only a start time counts the seconds from it")
    }

    static func secondsCountFromSince(_ suite: TestSuite) {
        let now = start.addingTimeInterval(754.6)
        suite.expect(RestingStatus.seconds(since: start, now: now, language: .enUS) == "754s",
                     "the seconds since the start, whole, written as Nexus Agent writes them in English")
        suite.expect(RestingStatus.seconds(since: start, now: now, language: .ja) == "754秒",
                     "and as the person's language writes them")
    }

    static func aFutureSinceCountsFromZero(_ suite: TestSuite) {
        suite.expect(RestingStatus.seconds(since: start.addingTimeInterval(30), now: start, language: .enUS) == "0s",
                     "a start time in the future counts from 0, never down")
    }

    static func longWordsAreOneLineOfTwelve(_ suite: TestSuite) {
        let long = "line one\nline two \u{202E}" + String(repeating: "x", count: 500)
        guard case .words(let drawn)? = wing(status(.busy, activity: .plain(long))) else {
            return suite.expect(false, "a status's long words are drawn, cut")
        }
        suite.expect(drawn.count == 12 && drawn == "line one li…" && !drawn.contains("\n")
                         && !drawn.unicodeScalars.contains("\u{202E}"),
                     "a text of 500 characters with a line break becomes one line of 12, the last an ellipsis")
        let words = UIText.languages(LocalizedText(["en": "3 run", "fr": "3 en cours"]))
        suite.expect(wing(status(.busy, activity: words), language: .fr) == .words("3 en cours")
                         && wing(status(.busy, activity: words), language: .de) == .words("3 run"),
                     "the words follow the person's language, English where there are none in it")
    }

    static func nexusOutranksATool(_ suite: TestSuite) {
        suite.expect(wing(status(.failure, activity: "3"), nexusRunning: true) == nil
                         && wing(nil, nexusRunning: true) == nil,
                     "while a Nexus session runs the wing draws Nexus, whatever a tool says")
    }

    static func theWordsAreTheShownMarks(_ suite: TestSuite) {
        let tools = [(first, status(.busy, activity: "3")), (second, status(.failure))]
        suite.expect(RestingStatus.rightWing(tools: tools, nexusRunning: false, language: .enUS) == .allowance,
                     "the worse mark has no words, so the percent is drawn, never another tool's words")
        let worded = [(first, status(.ok)), (second, status(.failure, activity: "2"))]
        suite.expect(RestingStatus.rightWing(tools: worded, nexusRunning: false, language: .enUS) == .words("2"),
                     "the shown mark's words are drawn")
        suite.expect(RestingStatus.rightWing(tools: [], nexusRunning: false, language: .enUS) == .allowance,
                     "no tool, the percent")
    }

    static func onlySecondsTickEverySecond(_ suite: TestSuite) {
        suite.expect(RestingStatus.ticksEverySecond(.seconds(since: start))
                         && !RestingStatus.ticksEverySecond(.words("3"))
                         && !RestingStatus.ticksEverySecond(.allowance) && !RestingStatus.ticksEverySecond(nil),
                     "only a count of seconds needs the wing's clock every second; the rest keep its six")
    }

    static func theButtonSaysTheWordsButNotTheSeconds(_ suite: TestSuite) {
        let said = RestingStatus.words(for: status(.busy, text: "Checks are running", activity: "3"), toolName: "GitHub",
                                       language: .enUS, strings: english)
        suite.expect(said == "GitHub: Checks are running, 3"
                         && RestingStatus.buttonTitle("Open Dynamic Island", saying: said, language: .enUS)
                         == "Open Dynamic Island, GitHub: Checks are running, 3",
                     "the button says the mark's words, then the tool's few words after a comma")
        suite.expect(RestingStatus.words(for: status(.busy, text: "Deploying", since: start), toolName: "Deploys",
                                         language: .enUS, strings: english) == "Deploys: Deploying",
                     "the seconds are not said: they would rename the button every second")
        let japanese = RestingStatus.words(for: status(.busy, text: "実行中", activity: "3"), toolName: "GitHub",
                                           language: .ja, strings: FeatureStrings.externalTools(.ja))
        suite.expect(japanese == "GitHub：実行中、3", "the pause before the words is written the way the language writes it")
    }
}

/// What the wing does with them: the percent beside a mark with no words.
extension ToolStatusTests {
    static func aMarkWithoutWordsLeavesThePercent(_ suite: TestSuite) {
        for state in states {
            let wing = RestingStatus.rightWing(tools: [(first, status(state, text: "Deploying"))], nexusRunning: false,
                                               language: .enUS)
            suite.expect(wing == .allowance && !RestingStatus.ticksEverySecond(wing),
                         "a mark without words leaves the percent, and the wing's clock its six seconds (\(state))")
        }
    }
}
