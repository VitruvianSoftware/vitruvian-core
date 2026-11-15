// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianAtriumCore
import VitruvianAtriumDesign
import VitruvianAtriumServices
import VitruvianAtriumUI

/// The select-all box's three states and what its next click does. The
/// uninstaller's own select-all runs in UninstallerFlowTests.
enum UninstallerBulkSelectionTests {
    private typealias Bulk = UninstallerSupport.BulkSelection

    static func run(_ suite: TestSuite) {
        suite.expect(Bulk(included: 0, total: 0) == .none,
                     "an empty results list shows an empty box")
        suite.expect(Bulk(included: 0, total: 3) == .none,
                     "no chosen rows show an empty box")
        suite.expect(Bulk(included: 1, total: 3) == .some,
                     "some chosen rows show a mixed box")
        suite.expect(Bulk(included: 3, total: 3) == .all,
                     "every chosen row shows a checked box")
        suite.expect(Bulk(included: 2, total: 2) == .all,
                     "a full list of two reads the same as a full list of many")

        suite.expect(Bulk.none.nextInclude && Bulk.some.nextInclude,
                     "clicking an empty or mixed box selects everything")
        suite.expect(!Bulk.all.nextInclude,
                     "clicking a full box clears the selection")
    }
}
