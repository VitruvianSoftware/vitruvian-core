// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import Foundation
import VitruvianCore
import VitruvianToolProtocol

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
