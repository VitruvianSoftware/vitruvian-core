// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianServices

/// Builds the production selection rows and records what their actions type
/// and copy, instead of posting keys or changing the clipboard.
enum CommandBarSelectionTests {
    static func run(_ suite: TestSuite) {
        let strings = FeatureStrings.commandBar(.enUS)
        var typed: [String] = []
        var copied: [String] = []
        var searched: [String] = []
        func rows(_ text: String, exactly selected: String? = nil, typesOver: Bool = true) -> [CommandBarEntry] {
            CommandBarCatalog.selectionEntries(text, exactly: selected, typesOver: typesOver, bar: strings,
                                               typeOver: { typed.append($0) },
                                               copy: { copied.append($0) },
                                               useInSearch: { searched.append($0) })
        }

        let selected = " \tHello world\n"
        let hello = rows("Hello world", exactly: selected)
        hello.first { $0.id == "selection.upper" }?.run(nil)
        suite.expect(typed == [selected.localizedUppercase],
                     "case changes preserve surrounding spaces and the selected line break")
        hello.first { $0.id == "selection.copy" }?.run(nil)
        hello.first { $0.id == "selection.search" }?.run(nil)
        suite.expect(copied == ["Hello world"] && searched == ["Hello world"],
                     "copy and search continue to use the trimmed selection")

        let caseIDs: Set<String> = ["selection.upper", "selection.lower", "selection.titleCase"]
        for count in [4_999, 5_000, 100_000] {
            let exact = String(repeating: " ", count: count) + "a"
            let bounded = rows("a", exactly: exact)
            suite.expect(bounded.contains { caseIDs.contains($0.id) } == (exact.count <= 5_000),
                         "the replacement limit includes all \(count) surrounding spaces")
            if exact.count <= 5_000 {
                bounded.first { $0.id == "selection.upper" }?.run(nil)
                suite.expect(typed.last == exact.localizedUppercase,
                             "a selection at the insertion limit retains every character")
            }
            suite.expect(bounded.contains { $0.id == "selection.copy" }
                         && bounded.contains { $0.id == "selection.search" },
                         "long exact selections retain actions that do not type over them")
        }
        let markers = rows("hello", exactly: "hello", typesOver: false)
        suite.expect(!markers.contains { caseIDs.contains($0.id) }
                     && markers.contains { $0.id == "selection.copy" },
                     "text marker selections offer read actions without unsafe case replacement")
        rows("hello").first { $0.id == "selection.upper" }?.run(nil)
        suite.expect(typed.last == "HELLO",
                     "callers without an exact selection keep the original case behavior")
        suite.expect(rows("").isEmpty, "empty selections do not produce rows")
    }
}
