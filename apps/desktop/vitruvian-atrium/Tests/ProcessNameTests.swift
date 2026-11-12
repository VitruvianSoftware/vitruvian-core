// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

/// Names in the resource lists come from the module's own lookup, given the
/// three answers the system would give, so the fallbacks are checked whatever
/// processes this Mac lets the tests read.
enum ProcessNameContract {
    static func run(_ suite: TestSuite) {
        let appNames: [pid_t: String] = [501: "Safari"]
        let kernelNames: [pid_t: String] = [501: "Safari", 502: "loginwindow"]
        let paths: [pid_t: String] = [
            100: "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
            104: "/usr/libexec/runningboardd",
            502: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
        ]
        func name(_ pid: pid_t) -> String {
            ResponsibleProcess.displayName(pid: pid, fallback: "pid \(pid)",
                                           appName: { appNames[$0] },
                                           kernelName: { kernelNames[$0] },
                                           executablePath: { paths[$0] })
        }
        suite.expect(name(501) == "Safari", "an app keeps its localized name")
        suite.expect(name(502) == "loginwindow", "a process of the same user keeps its kernel name")
        // The GPU list showed "pid 100" for WindowServer: macOS 27 refuses
        // proc_name for another user's process but still gives its path.
        suite.expect(name(100) == "WindowServer", "another user's process is named from its executable")
        suite.expect(name(104) == "runningboardd", "a daemon is named from its executable")
        suite.expect(name(999) == "pid 999", "a process that is gone keeps the caller's hint")
    }
}
