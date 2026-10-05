// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

// The runner lists every independently selectable suite. A filtered run says
// exactly which suites ran; an unknown or empty selection is an error.
@main
struct MetricsTests {
    static func main() {
        // Line-buffered, so a suite that crashes the run still leaves the
        // names of the suites that finished before it in the test log.
        setvbuf(stdout, nil, _IOLBF, 0)
        let suite = TestSuite()
        let groups = TestGroups.all(suite)
        var selected = Set<String>()
        var listOnly = false
        for argument in CommandLine.arguments.dropFirst() {
            if argument == "--list" {
                listOnly = true
                continue
            }
            guard argument.hasPrefix("--suite="),
                  groups.contains(where: { $0.0 == String(argument.dropFirst(8)) }) else {
                fputs("Unknown test selection: \(argument)\n", stderr)
                exit(2)
            }
            selected.insert(String(argument.dropFirst(8)))
        }
        if listOnly {
            groups.forEach { print($0.0) }
            exit(0)
        }
        for (name, body) in groups where selected.isEmpty || selected.contains(name) {
            suite.run(name, body)
        }
        suite.finish()
    }
}
