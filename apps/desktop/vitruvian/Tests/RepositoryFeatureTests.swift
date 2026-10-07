// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat
import VitruvianCore
import VitruvianDesign
import VitruvianServices
import VitruvianUI

enum RepositoryFeatureTests {
    /// What a Homebrew wait asked its stand-ins, from the worker thread it
    /// runs on. Only that thread writes it, and the test reads it once the
    /// wait has ended.
    private nonisolated final class BrewWaitLog: @unchecked Sendable {
        var silences: [TimeInterval]
        var questions = 0
        var stops = 0

        init(silences: [TimeInterval]) {
            self.silences = silences
        }

        /// The next silence, then a whole second once the list runs out.
        func silence() -> TimeInterval {
            questions += 1
            return silences.isEmpty ? 1 : silences.removeFirst()
        }
    }

    /// Runs `HomebrewManager.awaitExit` with a 10 ms limit on a worker thread,
    /// and says how often it asked for the silence and stopped the command,
    /// or that it was still waiting after five seconds.
    private static func brewWait(_ finished: DispatchSemaphore, silences: [TimeInterval]) -> String {
        let waitLog = BrewWaitLog(silences: silences)
        let ended = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            HomebrewManager.awaitExit(finished, silenceLimit: 0.01,
                                      silence: { waitLog.silence() }, stop: { waitLog.stops += 1 })
            ended.signal()
        }
        guard ended.wait(timeout: .now() + 5) == .success else { return "still waiting" }
        return "asked \(waitLog.questions), stopped \(waitLog.stops)"
    }

    /// A scratch folder for one script run; nothing is in it yet.
    private static func scratchFolder(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("vitru-\(name)-\(UUID().uuidString)")
    }

    /// Writes an executable stand-in for a command that a script runs.
    private static func writeStub(_ name: String, in folder: URL, _ body: String) -> Bool {
        let stub = folder.appendingPathComponent(name)
        return (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil
            && (try? ("#!/bin/sh\n" + body + "\n").write(to: stub, atomically: true, encoding: .utf8)) != nil
            && (try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)) != nil
    }

    /// Puts a small file at `path`, with the folders above it.
    private static func stageScratchFile(_ path: String) -> Bool {
        (try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                  withIntermediateDirectories: true)) != nil
            && FileManager.default.createFile(atPath: path, contents: Data("scratch".utf8))
    }

    /// A Homebrew whose install fails and whose lists come back empty. The
    /// re-read after the failure runs, and the reason the failure gave is
    /// still on screen once it has; with no brew at all a re-read keeps it
    /// too, and only a plain refresh clears it.
    private static func brewBannerSurvivesRefresh(_ suite: TestSuite) {
        let folder = scratchFolder("brew")
        defer { try? FileManager.default.removeItem(at: folder) }
        let calls = folder.appendingPathComponent("calls.log")
        let failure = "Error: sample-tool is disabled"
        let staged = writeStub("brew", in: folder, """
            echo "$1" >> "\(calls.path)"
            case "$1" in
                install) echo "\(failure)"; exit 1 ;;
                info|outdated) echo '{"formulae":[],"casks":[]}' ;;
            esac
            """)
        var standIn: String? = folder.appendingPathComponent("brew").path
        let manager = HomebrewManager(locateBrew: { standIn })
        func ran() -> [String] {
            ((try? String(contentsOf: calls, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        }
        manager.install(HomebrewPackage(kind: .cask, name: "sample-tool", displayName: "Sample Tool",
                                        desc: nil, installedVersion: nil, stableVersion: nil, homepage: nil))
        // The first brew run waits on the login shell for its environment.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline,
              !(ran().count >= 3 && !manager.isLoadingInstalled && !manager.isLoadingOutdated) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        suite.expect(staged && ran() == ["install", "info", "outdated"]
                && manager.operationStatus?.result == .failed && manager.errorMessage == failure,
               "a failed operation re-reads the installed and outdated lists and keeps the reason it gave: "
               + "ran \(ran()), showing \(manager.errorMessage ?? "nothing")")
        standIn = nil
        manager.refreshInstalled(clearingError: false)
        let keptWithoutBrew = manager.errorMessage
        manager.refreshInstalled()
        suite.expect(keptWithoutBrew == failure && manager.errorMessage == nil && manager.brewPath == nil,
               "both banner clears in refreshInstalled are behind its parameter, so the reason "
               + "a failed operation gave survives the refresh that follows it")
    }

    /// What the bar learns from a search stays in this process: running a
    /// row saves its use and remembers the search in memory, no query habit
    /// is written back, and one stored by an earlier version is dropped.
    private static func queryHabitsStayInMemory(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "vitru.tests.query-habits")!
        defaults.removePersistentDomain(forName: "vitru.tests.query-habits")
        defer { defaults.removePersistentDomain(forName: "vitru.tests.query-habits") }
        defaults.set("{}", forKey: DefaultsKey.commandBarQueryHabits)
        CommandBarLearning.discardLegacyQueryHabits(in: defaults)
        let recorder = CommandBarRunRecorder(host: .init(
            field: {
                CommandBarRunRecorder.Field(mode: .search, query: "what", savedQuery: "",
                                            queryBeforeCompletion: nil, selectedText: "", isVisible: true)
            },
            hide: {}, type: { _ in }, defaults: defaults))
        recorder.finish(CommandBarEntry(id: "app.whatever", title: "Whatever", subtitle: "",
                                        icon: .symbol("app"), run: { _ in }),
                        value: nil)
        suite.expect(!recorder.queryHabitStore.store.isEmpty
                && defaults.string(forKey: DefaultsKey.commandBarUsage) != nil
                && defaults.object(forKey: DefaultsKey.commandBarQueryHabits) == nil,
               "query learning never persists query habits: the search is learned in memory, "
               + "its use is saved, and a stored habit is dropped")
    }

    /// What the real uninstall steps asked of the system. The steps run on the
    /// test's own thread here, and only it touches the log.
    private nonisolated final class TeardownLog: @unchecked Sendable {
        var events: [String] = []
        var readings: [(status: Int32, output: String)] = []
        var flagged = true
        var rule = false
        var password = true
        var fanDetached = true
        var mouseRestored = true
    }

    private static func recordedCalls(_ log: TeardownLog) -> SelfUninstall.SystemCalls {
        SelfUninstall.SystemCalls(
            suspendInterceptor: { interceptor in
                log.events.append("suspend \(interceptor)")
                return interceptor != .mouseAcceleration || log.mouseRestored
            },
            resumeBrightnessKeys: { log.events.append("resume brightness keys") },
            sleepFlagged: {
                log.events.append("flag")
                return log.flagged
            },
            probeSleep: {
                log.events.append("probe")
                if log.readings.isEmpty { return (1, "") }
                return log.readings.removeFirst()
            },
            restoreSleepWithoutPassword: {
                log.events.append("rule")
                return log.rule
            },
            restoreSleepAsAdministrator: { prompt in
                log.events.append("password: \(prompt)")
                return log.password
            },
            detachFanHelper: {
                log.events.append("fan helper")
                return log.fanDetached
            })
    }

    /// `SelfUninstall.Steps.system` is the real steps over the Mac's calls;
    /// here they run over recorded ones.
    private static func uninstallStepsAreTheRealOnes(_ suite: TestSuite) {
        let sleepOff: (status: Int32, output: String) = (0, "System-wide power settings:\n SleepDisabled\t\t1\n")
        let sleepOn: (status: Int32, output: String) = (0, "System-wide power settings:\n SleepDisabled\t\t0\n")
        let restoring = TeardownLog()
        restoring.readings = [sleepOff, sleepOn]
        let restoringSteps = SelfUninstall.Steps.wired(to: recordedCalls(restoring))
        let restored = restoringSteps.restoreSleepBeforeRemoval() && restoringSteps.detachFanControl()
        let refusing = TeardownLog()
        refusing.readings = [sleepOff, sleepOff]
        refusing.fanDetached = false
        let refusingSteps = SelfUninstall.Steps.wired(to: recordedCalls(refusing))
        let refused = !refusingSteps.restoreSleepBeforeRemoval() && !refusingSteps.detachFanControl()
        let asked: [String] = ["flag", "probe", "rule", "password: \(L10n.shared.s.adminPromptRecover)",
                               "probe", "fan helper"]
        suite.expect(restored && refused && restoring.events == asked && refusing.events == asked,
               "in-app uninstall aborts unless fans and normal sleep are restored before removal: "
               + "\(restoring.events), \(refusing.events)")

        // `Vitruvian --uninstall` has no password dialog. What it prints about
        // sleep follows the password-free restore, or a reading taken first
        // that sleep is on: a restore result thrown away would print sleep as
        // still off right after the rule put it back.
        func commandLine(flagged: Bool = true, reading: (status: Int32, output: String), rule: Bool) -> String {
            let log = TeardownLog()
            log.flagged = flagged
            log.readings = [reading]
            log.rule = rule
            let report = SelfUninstall.commandLineSleepReport(recordedCalls(log)) ?? "nothing"
            return report + " after " + log.events.joined(separator: ", ")
        }
        let reports = [
            commandLine(flagged: false, reading: sleepOff, rule: true),
            commandLine(reading: sleepOff, rule: true),
            commandLine(reading: sleepOff, rule: false),
            commandLine(reading: sleepOn, rule: false),
            commandLine(reading: (1, ""), rule: false),
        ]
        suite.expect(reports == [
            "nothing after flag",
            "UNINSTALL: normal sleep restored after flag, probe, rule",
            "UNINSTALL: sleep is still disabled after flag, probe, rule",
            "UNINSTALL: normal sleep restored after flag, probe, rule",
            "UNINSTALL: sleep is still disabled after flag, probe, rule",
        ], "neither uninstall path discards the result of restoring sleep: \(reports)")

        // The permission teardown stops every input interceptor, Cleaning
        // Mode first and at once: deactivating it later re-syncs the services
        // it paused and re-arms the taps just stopped. The keyboard taps are
        // among them, and the brightness keys come back with the rest.
        let teardown = TeardownLog()
        teardown.mouseRestored = false
        let teardownSteps = SelfUninstall.Steps.wired(to: recordedCalls(teardown))
        let released = teardownSteps.suspendInputInterceptors()
        teardownSteps.resumeBrightness()
        let interceptors = SelfUninstall.InputInterceptor.allCases
        suite.expect(teardown.events.first == "suspend cleaningMode",
               "permission reset removes the cleaning input tap synchronously, before the taps it would re-arm")
        let keyboardTaps: [SelfUninstall.InputInterceptor] = [.textSnippets, .quitProtection, .brightnessKeys]
        let stopsKeyboardTaps = keyboardTaps.allSatisfy { interceptors.contains($0) }
        let everyStop: [String] = interceptors.map { "suspend \($0)" } + ["resume brightness keys"]
        suite.expect(teardown.events == everyStop && stopsKeyboardTaps && !released,
               "the permission teardown stops every persistent keyboard tap, and waits for mouse "
               + "acceleration: \(teardown.events)")
    }

    /// The permission teardown stops the two brightness key taps and nothing
    /// else of the display side: a revoked permission must not undo a dimmed
    /// picture or bring back a display the user switched off.
    private static func brightnessTeardownKeepsTheDisplays(_ suite: TestSuite) {
        let desk = BrightnessRig.Desk()
        defer { desk.tearDown() }
        let panel = BrightnessRig.Display(id: 1, systemLevel: 0.5)
        panel.builtIn = true
        desk.displays = [panel, BrightnessRig.Display(id: 2), BrightnessRig.Display(id: 3)]
        let service = BrightnessService(environment: desk.environment)
        service.start()
        desk.drain()
        service.setBrightness(0.5, for: 2)
        desk.drain()
        if let third = service.displays.first(where: { $0.id == 3 }) {
            service.toggleDisplay(third)
        }
        desk.drain()
        let prepared = desk.configurations == ["off:3"] && !desk.display(2).gammaWrites.isEmpty
        let suspendedBefore = service.inputTapsAreSuspended
        desk.events = []
        service.suspendInputTaps()
        desk.drain()
        suite.expect(prepared && !suspendedBefore && service.inputTapsAreSuspended && desk.events.isEmpty,
               "the permission teardown holds the brightness key taps off and leaves the pictures and "
               + "the displays as they were, found \(desk.events)")
    }

    static func run(_ suite: TestSuite) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        // MARK: URL cleaning

        expectEqual(URLCleaning.clean("https://example.com/path?utm_source=news&id=42&fbclid=abc")?.url ?? "",
                    "https://example.com/path?id=42",
                    "URL cleaner removes tracking and preserves useful query")
        expectEqual(URLCleaning.clean(" https://example.com/?GCLID=one&utm_campaign=x#section ")?.url ?? "",
                    "https://example.com/#section",
                    "URL cleaner is case-insensitive and preserves fragments")
        expectEqual(URLCleaning.clean("https://example.com/?id=42")?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner leaves clean URLs alone")
        let customURLParameters = URLCleaning.customParameters(from: " Ref, source\nref,  ")
        suite.expect(customURLParameters == ["ref", "source"],
               "URL cleaner normalizes comma-separated custom parameter names")
        let customURLRules = URLCleaning.rules(globalNames: " Ref, source\nref,  ",
                                               siteNames: nil, disabledNames: nil)
        expectEqual(URLCleaning.clean("https://example.com/?REF=one&id=42&source=two",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner removes custom parameters by exact case-insensitive name")
        expectEqual(URLCleaning.clean("https://example.com/?reference=one",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?reference=one",
                    "URL cleaner does not treat custom parameter names as prefixes")
        // A grouped Form keeps a label column even for an empty label, which
        // left every field on the right half of its row; and the panels'
        // outlines answer raised contrast. Both are drawn there.
        SettingsLayoutContract.run(suite)

        // Rules are stored as a difference from the built-in tables, never as
        // a copy of them, so names a later version adds still reach someone
        // who has already edited their rules.
        let keptUTM = URLCleaning.rules(globalNames: nil, siteNames: nil, disabledNames: "|utm_*")
        expectEqual(URLCleaning.clean("https://example.com/?utm_source=news&fbclid=abc&id=1",
                                      rules: keptUTM)?.url ?? "",
                    "https://example.com/?utm_source=news&id=1",
                    "switching the utm row off keeps every utm name and leaves the rest cleaning")
        let keptShareToken = URLCleaning.rules(globalNames: nil, siteNames: nil,
                                               disabledNames: "youtube.com|si")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=1&si=x&feature=share",
                                      rules: keptShareToken)?.url ?? "",
                    "https://www.youtube.com/watch?v=1&si=x",
                    "a switched off site name stays in the link while its siblings still go")
        let addedSiteRule = URLCleaning.rules(globalNames: nil, siteNames: "weibo.com|sudaref",
                                              disabledNames: nil)
        expectEqual(URLCleaning.clean("https://weibo.com/a?sudaref=x&id=1", rules: addedSiteRule)?.url ?? "",
                    "https://weibo.com/a?id=1",
                    "a name added to one site cleans that site")
        expectEqual(URLCleaning.clean("https://example.com/?sudaref=x", rules: addedSiteRule)?.url ?? "",
                    "https://example.com/?sudaref=x",
                    "a name added to one site never reaches another")
        suite.expect(URLCleaning.clean("https://example.com/?utm_source=a&fbclid=b&id=1")?.removed
                == ["utm_source", "fbclid"],
               "cleaning answers with the names it took out, in the order the link carried them")
        suite.expect(URLCleaning.outcome(for: nil, input: "nope") == .notAURL,
               "text that is not a link reads as no URL")
        let paddedLink = " https://example.com/?id=1 "
        suite.expect(URLCleaning.outcome(for: URLCleaning.clean(paddedLink), input: paddedLink) == .unchanged,
               "trimming alone does not count as a clean")

        let editedRules = URLCleaning.rules(globalNames: "ref", siteNames: "weibo.com|sudaref",
                                            disabledNames: "|fbclid")
        let ruleGroups = URLCleaning.ruleGroups(rules: editedRules)
        suite.expect(ruleGroups.first?.site == URLCleaning.allSites,
               "the rules that apply everywhere lead the list")
        suite.expect(ruleGroups.first?.entries.first?.name == URLCleaning.utmWildcard,
               "one row stands for every utm name")
        suite.expect(ruleGroups.first?.entries.allSatisfy {
            $0.name == URLCleaning.utmWildcard || !$0.name.hasPrefix("utm_")
        } == true, "the utm names that row already covers are not listed again")
        suite.expect(ruleGroups.first?.entries.contains { $0.name == "fbclid" && !$0.isEnabled } == true,
               "a switched off built-in stays listed so it can be switched back on")
        suite.expect(ruleGroups.first?.entries.contains { $0.name == "ref" && !$0.isBuiltIn } == true,
               "names the user added share the list with the built-in ones")
        suite.expect(ruleGroups.contains { $0.site == "weibo.com" },
               "a site the user added gets a row of its own")
        suite.expect(ruleGroups.contains { $0.site == "youtube.com" },
               "every built-in site is listed")
        expectEqual(URLCleaning.clean("https://www.xiaohongshu.com/?shareRedId=a&exSource=b&id=1")?.url ?? "",
                    "https://www.xiaohongshu.com/?id=1",
                    "a built-in name spelled in mixed case by the site is still removed")
        let upperCaseBuiltIns = URLCleaning.ruleGroups(rules: .none)
            .flatMap(\.entries).map(\.name).filter { $0 != $0.lowercased() }
        suite.expect(upperCaseBuiltIns.isEmpty,
               "built-in names are lowercase, since matching and switched off names are: \(upperCaseBuiltIns)")
        expectEqual(URLCleaning.siteKey(from: " https://WWW.Weibo.com/path?x=1 ") ?? "",
                    "weibo.com", "the site field takes a pasted link and keeps the host")
        suite.expect(URLCleaning.siteKey(from: "not a host") == nil,
               "text that is not a host is refused rather than stored")
        expectEqual(URLCleaning.parameterName(from: " Ref ") ?? "", "ref",
                    "a parameter name is trimmed and lowercased")
        suite.expect(URLCleaning.parameterName(from: "a=b") == nil,
               "a name a query cannot carry as one parameter is refused")
        suite.expect(URLCleaning.tokens(from: "youtube.com|si, |ref") == ["youtube.com": ["si"], "": ["ref"]],
               "stored tokens read back as site and global names")
        expectEqual(URLCleaning.storageValue(forTokens: URLCleaning.tokens(from: "youtube.com|si, |ref")),
                    "|ref,youtube.com|si", "tokens are stored in a stable order")

        suite.expect([DefaultsKey.urlCleanerCustomParameters,
                DefaultsKey.urlCleanerSiteParameters,
                DefaultsKey.urlCleanerDisabledParameters].allSatisfy {
                    Defaults.registeredDefaults[$0] as? String == ""
                        && SettingsBackupSupport.exportKeys().contains($0)
                },
               "URL cleaner rules start empty and travel in Settings backups")
        suite.expect(URLCleaning.clean("not a url") == nil,
               "URL cleaner rejects plain text")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1TY8J67EUB/?spm_id_from=333.1007.tianma.1-1-1.click&vd_source=3b2eea5")?.url ?? "",
                    "https://www.bilibili.com/video/BV1TY8J67EUB/",
                    "URL cleaner strips Bilibili share tracking")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90&vd_source=abc")?.url ?? "",
                    "https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90",
                    "URL cleaner keeps the Bilibili part number and playback position")
        expectEqual(URLCleaning.clean("https://search.bilibili.com/all?keyword=swift&from_source=webtop_search")?.url ?? "",
                    "https://search.bilibili.com/all?keyword=swift",
                    "URL cleaner keeps the Bilibili search keyword")
        expectEqual(URLCleaning.clean("https://youtu.be/TImSMeurR84?si=Xq1&t=42")?.url ?? "",
                    "https://youtu.be/TImSMeurR84?t=42",
                    "URL cleaner strips the YouTube share token and keeps the timestamp")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=TImSMeurR84")?.url ?? "",
                    "https://www.youtube.com/watch?v=TImSMeurR84",
                    "URL cleaner leaves a bare YouTube watch link alone")
        expectEqual(URLCleaning.clean("https://x.com/user/status/1?s=20&t=abc")?.url ?? "",
                    "https://x.com/user/status/1",
                    "URL cleaner strips X share tracking")
        expectEqual(URLCleaning.clean("https://example.com/?si=keep&t=keep&s=keep")?.url ?? "",
                    "https://example.com/?si=keep&t=keep&s=keep",
                    "site rules never leak onto other hosts")
        expectEqual(URLCleaning.clean("https://open.spotify.com/track/abc?si=xyz")?.url ?? "",
                    "https://open.spotify.com/track/abc",
                    "site rules match subdomains")
        expectEqual(URLCleaning.clean("https://www.reddit.com/r/swift/comments/abc/?%24deep_link=true&%243p=x&share_id=y&sort=new")?.url ?? "",
                    "https://www.reddit.com/r/swift/comments/abc/?sort=new",
                    "URL cleaner strips Reddit's deep-link tracking in either spelling")

        suite.expect(URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.url", "public.url-name",
            "NSStringPboardType", "NSURLPboardType",
        ]), "a plain link copy can be rewritten")
        suite.expect(!URLCleaning.canRewritePasteboard(types: []),
               "an empty pasteboard is left alone")
        suite.expect(URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.html", "public.rtf", "com.apple.flat-rtfd",
            "public.utf16-external-plain-text",
        ]), "formatted copies of the same link are dropped by the rewrite, not protected")
        suite.expect(URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.url", "org.chromium.source-url",
            "org.chromium.web-custom-data", "com.apple.WebKit.custom-pasteboard-data",
            "dyn.ah62d4rv4gu8y6y4grf0gn5xbrzw1gydcr7u1e3cytf2gn",
        ]), "a browser's or a messaging app's private notes about the copy do not block the rewrite")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.url", "public.tiff", "public.png",
        ]), "a copied picture with its source link as text is left alone")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.file-url", "NSFilenamesPboardType",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "NSFilenamesPboardType",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "com.apple.pasteboard.promised-file-url",
            "com.apple.pasteboard.promised-file-content-type",
        ]), "a copied or promised file is left alone")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "com.adobe.pdf",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.mpeg-4",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "com.apple.webarchive",
        ]), "a document, a movie or a web archive next to the text is left alone")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "org.nspasteboard.ConcealedType",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "org.nspasteboard.TransientType",
        ]), "a concealed or transient copy is never rewritten")

        // MARK: Homebrew command building and parsing

        // An operation waits for brew on a semaphore bounded by silence, never
        // on waitUntilExit: a command that has said nothing for the limit is
        // stopped and the wait ends, one that keeps talking is waited for, and
        // one that has exited is not stopped at all.
        let brewNeverExits = DispatchSemaphore(value: 0)
        // Signalled after it is made, so it ends back at its starting value.
        let brewExited = DispatchSemaphore(value: 0)
        brewExited.signal()
        let brewWaits = [
            brewWait(brewNeverExits, silences: []),
            brewWait(brewNeverExits, silences: [0, 0]),
            brewWait(brewExited, silences: []),
        ]
        suite.expect(brewWaits == ["asked 1, stopped 1", "asked 3, stopped 1", "asked 0, stopped 0"],
               "Homebrew operations wait on a bounded semaphore, not waitUntilExit: \(brewWaits)")

        suite.expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        suite.expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        suite.expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "Error: Refusing to load formula foo from untrusted tap someone/sometap.\nRun `brew trust someone/sometap` to trust it.")
            == "someone/sometap",
               "untrusted tap name is extracted from Homebrew's refusal")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput: "Error: no such formula") == nil,
               "other Homebrew errors extract no tap")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "from untrusted tap ../evil") == nil,
               "a tap name that fails token validation is rejected")
        let trustCommand = HomebrewCommandBuilder.trustTap(brewPath: "/opt/homebrew/bin/brew", tap: "someone/sometap")
        suite.expect(trustCommand.arguments == ["trust", "--tap", "someone/sometap"],
               "trust command targets the tap explicitly")
        suite.expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        suite.expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        suite.expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "sample-tool",
                                   displayName: "Sample Tool", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        suite.expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        suite.expect(HomebrewCommandBuilder.outdated(brewPath: brewPath).arguments
               == ["outdated", "--json=v2"],
               "Homebrew outdated command uses read-only JSON v2 output")
        suite.expect(HomebrewCommandBuilder.update(brewPath: brewPath).arguments
               == ["update"],
               "Homebrew update command refreshes Homebrew metadata")
        suite.expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "sample-tool"],
               "cask install command uses --cask")
        suite.expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "sample-tool"],
               "cask uninstall command uses --cask")
        suite.expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: cask).arguments
               == ["upgrade", "--cask", "sample-tool"],
               "cask upgrade command uses --cask")
        let formula = HomebrewPackage(kind: .formula, name: "jq",
                                      displayName: "jq", desc: nil,
                                      installedVersion: "1.8.1", stableVersion: nil, homepage: nil)
        suite.expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: formula).arguments
               == ["upgrade", "jq"],
               "formula upgrade command uses separated arguments")
        suite.expect(HomebrewCommandBuilder.upgradeAll(brewPath: brewPath).arguments
               == ["upgrade"],
               "Homebrew update all command upgrades all outdated packages")

        // brew exits non-zero when it could not do all of a run, not only when it
        // did none of it, so the installed and outdated lists have to be re-read
        // after a failed operation too, with the reason it gave still on screen.
        let operationEnds = [
            HomebrewOperationEnd(status: 1, cancelRequested: true, output: "Error: Interrupted"),
            HomebrewOperationEnd(status: 1, cancelRequested: false,
                                 output: "sudo: a terminal is required to read the password"),
            HomebrewOperationEnd(status: 1, cancelRequested: false, output: "Error: sample-tool is disabled"),
        ]
        suite.expect(operationEnds == [.cancelled, .needsTerminal, .failed]
                && operationEnds.allSatisfy { $0.refresh == .keepingError },
               "the cancelled, needs-terminal and failed operation paths all re-read, "
               + "found \(operationEnds)")
        let succeededEnd = HomebrewOperationEnd(status: 0, cancelRequested: true, output: "")
        let untrustedEnd = HomebrewOperationEnd(
            status: 1, cancelRequested: false,
            output: "Error: Refusing to load formula foo from untrusted tap someone/sometap.")
        let succeededClears: Bool = succeededEnd == .succeeded && succeededEnd.refresh == .clearingError
        let untrustedKeepsPrompt: Bool = untrustedEnd == .untrustedTap("someone/sometap")
            && untrustedEnd.refresh == nil
        suite.expect(succeededClears && untrustedKeepsPrompt,
               "a successful operation re-reads with a clean banner, and an untrusted tap keeps its prompt")
        brewBannerSurvivesRefresh(suite)
        suite.expect(HomebrewOperation.Action.install.runningSystemImage == "arrow.down.circle.fill",
               "Homebrew install status uses a download icon")
        suite.expect(HomebrewOperation.Action.uninstall.runningSystemImage == "trash.circle.fill",
               "Homebrew uninstall status uses a trash icon")
        suite.expect(HomebrewOperation.Action.upgrade.runningSystemImage == "arrow.up.circle.fill",
               "Homebrew package update status uses an update icon")
        suite.expect(HomebrewOperation.Action.updateHomebrew.runningSystemImage == "arrow.triangle.2.circlepath",
               "Homebrew metadata refresh status uses a refresh icon")
        suite.expect(HomebrewOperation.Action.uninstall.clearsSelectionOnSuccess,
               "Homebrew uninstall clears details for the package that left the installed list")
        suite.expect(!HomebrewOperation.Action.install.clearsSelectionOnSuccess
                && !HomebrewOperation.Action.upgrade.clearsSelectionOnSuccess,
               "Homebrew install and upgrade preserve package details after success")
        suite.expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        suite.expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
               "Homebrew installer command matches the official install script entrypoint")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/zsh"),
                    "/Users/test/.zprofile",
                    "Homebrew shell setup uses zprofile for zsh")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/bash"),
                    "/Users/test/.bash_profile",
                    "Homebrew shell setup uses bash_profile for bash")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/opt/homebrew/bin/fish"),
                    "/Users/test/.config/fish/config.fish",
                    "Homebrew shell setup uses the interactive shell config")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/bin/zsh"),
                    #"eval "$(/opt/homebrew/bin/brew shellenv)""#,
                    "Homebrew shell setup line uses brew shellenv")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/opt/homebrew/bin/fish"),
                    "eval (/opt/homebrew/bin/brew shellenv fish)",
                    "Homebrew shell setup line matches the interactive shell")
        expectEqual(HomebrewAnalytics.url(kind: .formula).absoluteString,
                    "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json",
                    "Homebrew formula popularity uses install-on-request analytics")
        expectEqual(HomebrewAnalytics.url(kind: .cask).absoluteString,
                    "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json",
                    "Homebrew cask popularity uses cask install analytics")
        do {
            let originalLocale = MetricFormat.locale
            defer { MetricFormat.locale = originalLocale }
            // Run independently of both the Mac's region and other suites.
            for (region, thousands, millions) in [
                ("en_US_POSIX", "1.2K", "1.2M"),
                ("pt_BR", "1,2K", "1,2M"),
            ] {
                MetricFormat.locale = Locale(identifier: region)
                expectEqual(HomebrewAnalytics.compactCount(999), "999",
                            "Homebrew popularity under 1K stays plain in \(region)")
                expectEqual(HomebrewAnalytics.compactCount(1_250), thousands,
                            "Homebrew popularity compacts thousands in \(region)")
                expectEqual(HomebrewAnalytics.compactCount(1_200_000), millions,
                            "Homebrew popularity compacts millions in \(region)")
            }
        }
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        suite.expect(shellSetupCommand.hasPrefix("/bin/sh -c ")
                && shellSetupCommand.contains("PROFILE=/Users/test/.zprofile")
                && shellSetupCommand.hasSuffix(#"; eval "$(/opt/homebrew/bin/brew shellenv)"; brew --version"#),
               "Homebrew shell setup command targets the detected profile")
        suite.expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        let alternateShellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(
            brewPath: brewPath,
            homeDirectory: "/Users/test",
            shellPath: "/opt/homebrew/bin/fish"
        )
        suite.expect(alternateShellSetupCommand.hasPrefix("/bin/sh -c ")
                && alternateShellSetupCommand.contains("/bin/mkdir -p /Users/test/.config/fish")
                && alternateShellSetupCommand.hasSuffix("; eval (/opt/homebrew/bin/brew shellenv fish); brew --version"),
               "Homebrew shell setup creates and activates the interactive shell config")

        // The login shell's exports reach brew through an allowlist (issue #1290).
        let loginShell = HomebrewEnvironment.loginShellCommand(shellPath: "/bin/zsh")
        suite.expect(loginShell.executable == "/bin/zsh"
                && loginShell.arguments.contains("-l")
                && loginShell.arguments.contains("-i")
                && (loginShell.arguments.last?.hasSuffix("/usr/bin/env -0") ?? false)
                && (loginShell.arguments.last?.contains(HomebrewEnvironment.dumpMarker) ?? false),
               "Homebrew asks the user's shell as a login and interactive shell, so ~/.zshrc is read too, "
               + "and marks where the NUL-separated environment starts")
        let envDump = Data(("HOME=/Users/test\0https_proxy=http://127.0.0.1:7890\0MULTI=a\nb\0"
                            + "EQUALS=x=y\0EMPTY=\0noequals\0Welcome back\nHOMEBREW_API_DOMAIN=https://mirror.example/api\0").utf8)
        let parsedEnvironment = HomebrewEnvironment.parse(nullSeparated: envDump)
        expectEqual(parsedEnvironment["https_proxy"] ?? "", "http://127.0.0.1:7890",
                    "Homebrew environment parser reads a NAME=value entry")
        expectEqual(parsedEnvironment["MULTI"] ?? "", "a\nb",
                    "Homebrew environment parser keeps a newline inside a value; NUL is the only separator")
        expectEqual(parsedEnvironment["EQUALS"] ?? "", "x=y",
                    "Homebrew environment parser splits on the first equals sign only")
        suite.expect(parsedEnvironment["EMPTY"] == "" && parsedEnvironment["noequals"] == nil,
               "Homebrew environment parser keeps an empty value and drops an entry without one")
        suite.expect(!parsedEnvironment.keys.contains { $0.contains("Welcome") || $0.hasPrefix("HOMEBREW_") },
               "Homebrew environment parser drops an entry whose name is not an identifier, "
               + "such as startup output glued to the variable behind it")
        // What a real `bash -i` does: "no job control in this shell" on the shared
        // pipe, with no NUL of its own, so the first variable rides in behind it.
        let noisyDump = Data(("bash: no job control in this shell\nWelcome back\n"
                              + HomebrewEnvironment.dumpMarker
                              + "https_proxy=http://127.0.0.1:7890\0HOMEBREW_API_DOMAIN=https://mirror.example/api\0").utf8)
        let parsedNoisy = HomebrewEnvironment.parse(nullSeparated: noisyDump)
        expectEqual(parsedNoisy["https_proxy"] ?? "", "http://127.0.0.1:7890",
                    "Homebrew keeps the first variable of the dump when a startup file printed before it")
        expectEqual(parsedNoisy["HOMEBREW_API_DOMAIN"] ?? "", "https://mirror.example/api",
                    "Homebrew reads the rest of a dump that startup output preceded")
        suite.expect(parsedNoisy.count == 2,
               "Homebrew takes nothing a startup file printed as a variable, found \(parsedNoisy.keys.sorted())")
        let echoedMarker = Data(("startup echoed " + HomebrewEnvironment.dumpMarker + " itself\n"
                                 + HomebrewEnvironment.dumpMarker + "no_proxy=localhost\0").utf8)
        expectEqual(HomebrewEnvironment.parse(nullSeparated: echoedMarker)["no_proxy"] ?? "", "localhost",
                    "Homebrew takes the last marker, so a startup file echoing it cannot cut the dump short")
        let passedThrough = HomebrewEnvironment.passthrough([
            "PATH": "/tmp/evil:/usr/bin", "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib", "HOME": "/Users/test",
            "SHELL": "/bin/zsh", "HTTP_PROXY": "http://127.0.0.1:7890", "https_proxy": "http://127.0.0.1:7890",
            "ALL_PROXY": "socks5://127.0.0.1:7891", "no_proxy": "localhost", "HOMEBREW_API_DOMAIN": "https://mirror.example/api",
            "HOMEBREW_BOTTLE_DOMAIN": "https://mirror.example", "HOMEBREWX": "no", "homebrew_lower": "no",
        ])
        suite.expect(Set(passedThrough.keys) == ["https_proxy", "ALL_PROXY", "no_proxy",
                                           "HOMEBREW_API_DOMAIN", "HOMEBREW_BOTTLE_DOMAIN"],
               "Homebrew passes through only the proxy names brew itself keeps and HOMEBREW_* settings, "
               + "found \(passedThrough.keys.sorted())")
        suite.expect(HomebrewEnvironment.exportsFromLoginShell(shellPath: "").isEmpty
                && HomebrewEnvironment.exportsFromLoginShell(shellPath: "/nonexistent/shell", timeout: 1).isEmpty,
               "Homebrew contributes nothing when there is no login shell or it cannot start")
        suite.expect(HomebrewEnvironment.exportsFromLoginShell(shellPath: "/bin/sh").keys
                .allSatisfy(HomebrewEnvironment.isPassedThrough),
               "Homebrew never hands a login shell's whole environment to brew")
        let plainLogin = HomebrewEnvironment.loginShellCommand(shellPath: "/bin/zsh", interactive: false)
        suite.expect(plainLogin.arguments.contains("-l") && !plainLogin.arguments.contains("-i")
                && plainLogin.arguments.last == loginShell.arguments.last,
               "Homebrew's fallback asks for the same dump from a plain login shell")
        let resolvingEnvironment = HomebrewEnvironment.loginShellEnvironment(base: ["HOME": "/Users/test"])
        suite.expect(HomebrewEnvironment.resolvingVariable == "VITRUVIAN_RESOLVING_ENVIRONMENT"
                && resolvingEnvironment == ["HOME": "/Users/test", "VITRUVIAN_RESOLVING_ENVIRONMENT": "1"],
               "Homebrew runs the login shell with VITRUVIAN_RESOLVING_ENVIRONMENT=1 on top of the app's environment")
        // A real zsh reading startup files from a scratch ZDOTDIR, so the user's own are never touched.
        let zdotdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vitruvian-login-shell-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: zdotdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: zdotdir) }
        func startupExports(zshrc: String) -> [String: String] {
            try? "export HOMEBREW_API_DOMAIN=https://mirror.example/api\n"
                .write(to: zdotdir.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
            try? zshrc.write(to: zdotdir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
            return HomebrewEnvironment.exportsFromLoginShell(
                shellPath: "/bin/zsh",
                baseEnvironment: ["HOME": zdotdir.path, "ZDOTDIR": zdotdir.path, "PATH": "/usr/bin:/bin"])
        }
        let zshrcExports = startupExports(zshrc: "export https_proxy=http://127.0.0.1:7890\n"
                                          + "export HOMEBREW_SEEN_RESOLVING=$VITRUVIAN_RESOLVING_ENVIRONMENT\n")
        suite.expect(zshrcExports["HOMEBREW_API_DOMAIN"] == "https://mirror.example/api"
                && zshrcExports["https_proxy"] == "http://127.0.0.1:7890",
               "Homebrew reads exports from both ~/.zprofile and ~/.zshrc, found \(zshrcExports.keys.sorted())")
        expectEqual(zshrcExports["HOMEBREW_SEEN_RESOLVING"] ?? "", "1",
                    "Homebrew's login shell exposes VITRUVIAN_RESOLVING_ENVIRONMENT to startup files")
        // A multiplexer autostart that fails without a terminal and exits, or an exec into another shell.
        for takeover in ["multiplexer_autostart_failed_without_a_terminal=1; exit 0", "exec /bin/sh -c true"] {
            let fallbackExports = startupExports(zshrc: takeover + "\n")
            expectEqual(fallbackExports["HOMEBREW_API_DOMAIN"] ?? "", "https://mirror.example/api",
                        "Homebrew falls back to the plain login run when ~/.zshrc ends the shell early: \(takeover)")
        }
        suite.expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        suite.expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        suite.expect(HomebrewProgressParser.phase(in: "==> Installing Cask sample-tool",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        suite.expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask sample-tool",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        suite.expect(HomebrewProgressParser.phase(in: "==> Upgrading sample-formula",
                                            action: .upgrade) == .upgrading,
               "Homebrew progress parser detects upgrades")
        suite.expect(HomebrewProgressParser.phase(in: "Already up-to-date.",
                                            action: .updateHomebrew) == .refreshing,
               "Homebrew progress parser detects metadata refresh")
        suite.expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Sample.app'\u{001B}[0m")
               == "Moving App 'Sample.app'",
               "Homebrew progress parser cleans activity lines")
        suite.expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
               == "Error: Cask failed",
               "Homebrew progress parser hides command lines from visible errors")

        let homebrewJSON = """
        {
          "formulae": [
            {
              "name": "sample-formula",
              "full_name": "sample-formula",
              "desc": "Sample formula",
              "homepage": "https://example.com/sample-formula",
              "versions": { "stable": "1.8.1" },
              "installed": [{ "version": "1.8.1" }]
            },
            {
              "name": "tapped-formula",
              "full_name": "example/tap/tapped-formula",
              "desc": "Formula from a third-party tap",
              "homepage": "https://example.com/tapped-formula",
              "versions": { "stable": "2.0.0" },
              "installed": [{ "version": "1.0.0" }]
            }
          ],
          "casks": [
            {
              "token": "sample-tool",
              "name": ["Sample Tool"],
              "desc": "Sample cask",
              "homepage": "https://example.com/sample-tool",
              "version": "1.108.1",
              "installed": "1.107.0"
            },
            {
              "token": "tapped-tool",
              "full_token": "example/tap/tapped-tool",
              "name": ["Tapped Tool"],
              "desc": "Cask from a third-party tap",
              "homepage": "https://example.com/tapped-tool",
              "version": "2.0.0",
              "installed": "1.0.0"
            }
          ]
        }
        """
        let homebrewPackages = (try? HomebrewParser.parseInfoJSON(Data(homebrewJSON.utf8))) ?? []
        suite.expect(homebrewPackages.count == 4, "Homebrew JSON parser keeps formulae and casks")
        suite.expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        suite.expect(homebrewPackages.first(where: { $0.name == "sample-formula" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        let tappedFormula = homebrewPackages.first { $0.name == "example/tap/tapped-formula" }
        suite.expect(tappedFormula?.displayName == "example/tap/tapped-formula",
               "Homebrew parser keeps the canonical name for a formula from a tap")
        suite.expect(homebrewPackages.first(where: { $0.name == "sample-tool" })?.displayName == "Sample Tool",
               "Homebrew parser reads cask display name")
        let tappedCask = homebrewPackages.first { $0.name == "tapped-tool" }
        suite.expect(tappedCask != nil,
               "Homebrew parser identifies a cask from a tap by its short token")
        suite.expect(tappedCask?.displayName == "Tapped Tool",
               "Homebrew parser keeps the human-readable name for a cask from a tap")
        let cleanCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(homebrewJSON)) ?? []
        suite.expect(cleanCommandPackages.count == 4,
               "Homebrew command output parser keeps clean JSON")
        let noisyHomebrewOutput = """
        Warning: Skipping some beta metadata
        {"notice": "not package data"}
        \(homebrewJSON)
        Warning: A newer Homebrew beta changed an optional field
        """
        let noisyCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(noisyHomebrewOutput)) ?? []
        suite.expect(noisyCommandPackages.count == 4,
               "Homebrew command output parser accepts warnings around JSON")
        suite.expect(noisyCommandPackages.first(where: { $0.name == "sample-tool" })?.installedVersion == "1.107.0",
               "Homebrew command output parser keeps package data from noisy output")
        suite.expect((try? HomebrewParser.parseInfoCommandOutput("Warning: no JSON here")) == nil,
               "Homebrew command output parser rejects output without valid JSON")
        let outdatedJSON = """
        {
          "formulae": [
            {
              "name": "fmt",
              "installed_versions": ["12.1.0"],
              "current_version": "12.2.0",
              "pinned": false
            },
            {
              "name": "example/tap/tapped-formula",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ],
          "casks": [
            {
              "name": "sample-tool",
              "installed_versions": ["1.107.0"],
              "current_version": "1.108.1",
              "pinned": true
            },
            {
              "name": "tapped-tool",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ]
        }
        """
        let outdatedPackages = (try? HomebrewParser.parseOutdatedJSON(Data(outdatedJSON.utf8))) ?? [:]
        suite.expect(outdatedPackages.count == 4,
               "Homebrew outdated parser keeps formulae and casks")
        suite.expect(outdatedPackages["formula:fmt"]?.versionSummary == "12.1.0 -> 12.2.0",
               "Homebrew outdated parser renders installed to current version")
        suite.expect(outdatedPackages["cask:sample-tool"]?.isPinned == true,
               "Homebrew outdated parser reads pinned status")
        suite.expect(tappedFormula.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same ID for tapped formulae")
        suite.expect(tappedCask?.id == "cask:tapped-tool",
               "Homebrew installed cask data stays on the short token brew outdated reports")
        suite.expect(tappedCask.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same short-token ID for tapped casks")
        let noisyOutdatedOutput = """
        Warning: Homebrew updated metadata
        {"notice": "not outdated data"}
        \(outdatedJSON)
        """
        let noisyOutdatedPackages = (try? HomebrewParser.parseOutdatedCommandOutput(noisyOutdatedOutput)) ?? [:]
        suite.expect(noisyOutdatedPackages["formula:fmt"]?.currentVersion == "12.2.0",
               "Homebrew outdated command output parser accepts warnings around JSON")
        let orderingPackages = [
            HomebrewPackage(kind: .cask, name: "alpha-tool", displayName: "Alpha Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil),
            HomebrewPackage(kind: .cask, name: "beta-tool", displayName: "Beta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .cask, name: "beta-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "gamma-tool", displayName: "Gamma Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .formula, name: "gamma-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "delta-tool", displayName: "Delta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil)
        ]
        suite.expect(HomebrewPackageOrdering.updatesFirst(orderingPackages).map(\.name)
               == ["beta-tool", "gamma-tool", "alpha-tool", "delta-tool"],
               "Homebrew installed packages keep all pending updates first without reordering either group")
        let dependencyJSON = """
        {
          "formulae": [
            { "name": "app-a", "full_name": "app-a",
              "installed": [{ "version": "1", "installed_on_request": true,
                              "runtime_dependencies": [{ "full_name": "shared-lib" }, { "full_name": "deep-lib" }] }] },
            { "name": "app-b", "full_name": "example/tap/app-b",
              "installed": [{ "version": "1", "installed_on_request": true,
                              "runtime_dependencies": [{ "full_name": "shared-lib" }, { "full_name": "example/tap/tap-lib" }] }] },
            { "name": "shared-lib", "full_name": "shared-lib",
              "installed": [{ "version": "2", "installed_on_request": false,
                              "runtime_dependencies": [{ "full_name": "deep-lib" }] }] },
            { "name": "deep-lib", "full_name": "deep-lib",
              "installed": [{ "version": "3", "installed_on_request": false, "runtime_dependencies": [] }] },
            { "name": "tap-lib", "full_name": "example/tap/tap-lib",
              "installed": [{ "version": "4", "installed_on_request": false, "runtime_dependencies": [] }] },
            { "name": "cask-lib", "full_name": "cask-lib",
              "installed": [{ "version": "5", "installed_on_request": false, "runtime_dependencies": [] }] },
            { "name": "orphan-lib", "full_name": "orphan-lib",
              "installed": [{ "version": "6", "installed_on_request": false, "runtime_dependencies": [] }] }
          ],
          "casks": [
            { "token": "cask-app", "name": ["Cask App"], "installed": "1",
              "depends_on": { "formula": ["cask-lib"] } }
          ]
        }
        """
        let dependencyPackages = (try? HomebrewParser.parseInfoJSON(Data(dependencyJSON.utf8))) ?? []
        let folded = HomebrewDependencyGraph.fold(dependencyPackages, installed: dependencyPackages)
        let flat = HomebrewDependencyGraph.display(dependencyPackages,
                                                   installed: dependencyPackages,
                                                   groupDependencies: false)
        suite.expect(flat.rows.map(\.id) == dependencyPackages.map(\.id)
                     && flat.rows.count == dependencyPackages.count
                     && flat.dependencies.isEmpty
                     && flat.orphans.isEmpty,
                     "Homebrew flat mode retains every installed row in its incoming order and shows no nested duplicates or orphans")
        let grouped = HomebrewDependencyGraph.display(dependencyPackages,
                                                      installed: dependencyPackages,
                                                      groupDependencies: true)
        suite.expect(grouped.rows.map(\.id) == folded.rows.map(\.id)
                     && Set(grouped.dependencies.keys) == Set(folded.dependencies.keys)
                     && grouped.orphans.map(\.id) == folded.orphans.map(\.id),
                     "Homebrew grouped mode preserves the existing dependency layout")
        suite.expect(folded.rows.map(\.name) == ["cask-app", "app-a", "example/tap/app-b"]
                     && folded.orphans.map(\.name) == ["orphan-lib"],
                     "Homebrew keeps requested packages as rows and lists a dependency nothing needs as an orphan, found \(folded.rows.map(\.name)) and \(folded.orphans.map(\.name))")
        suite.expect(folded.dependencies["formula:app-a"]?.map(\.name) == ["deep-lib", "shared-lib"],
                     "Homebrew lists direct and transitive dependencies under a requested formula")
        suite.expect(folded.dependencies["formula:example/tap/app-b"]?.map(\.name)
                     == ["deep-lib", "example/tap/tap-lib", "shared-lib"],
                     "Homebrew lists a shared dependency under each parent and resolves tapped names")
        suite.expect(folded.dependencies["cask:cask-app"]?.map(\.name) == ["cask-lib"],
                     "Homebrew lists a cask's formula dependencies under the cask")
        let withUpdate = HomebrewPackageOrdering.updatesFirst(dependencyPackages.map { package in
            var package = package
            if package.name == "shared-lib" {
                package.update = HomebrewPackageUpdate(kind: .formula, name: "shared-lib",
                                                       installedVersions: ["2"], currentVersion: "3", isPinned: false)
            }
            return package
        })
        let updateFolded = HomebrewDependencyGraph.fold(withUpdate, installed: withUpdate)
        let flatWithUpdate = HomebrewDependencyGraph.display(withUpdate,
                                                             installed: withUpdate,
                                                             groupDependencies: false)
        suite.expect(flatWithUpdate.rows.map(\.id) == withUpdate.map(\.id)
                     && flatWithUpdate.rows.first?.name == "shared-lib",
                     "Homebrew flat mode keeps update-first ordering and includes dependencies as top-level rows")
        suite.expect(updateFolded.rows.map(\.name) == ["shared-lib", "cask-app", "app-a", "example/tap/app-b"]
                     && updateFolded.dependencies["formula:app-a"]?.map(\.name) == ["deep-lib", "shared-lib"],
                     "Homebrew keeps a reached dependency with an update as its own first row and under its parent, found \(updateFolded.rows.map(\.name))")
        let orphanUpdate = HomebrewPackageOrdering.updatesFirst(dependencyPackages.map { package in
            var package = package
            if package.name == "orphan-lib" {
                package.update = HomebrewPackageUpdate(kind: .formula, name: "orphan-lib",
                                                       installedVersions: ["6"], currentVersion: "7", isPinned: false)
            }
            return package
        })
        let orphanUpdateFolded = HomebrewDependencyGraph.fold(orphanUpdate, installed: orphanUpdate)
        suite.expect(orphanUpdateFolded.rows.first?.name == "orphan-lib" && orphanUpdateFolded.orphans.isEmpty,
                     "Homebrew keeps an orphan with an update as the first row, found \(orphanUpdateFolded.rows.map(\.name))")
        let formulaOnly = dependencyPackages.filter { $0.kind == .formula }
        let flatFormulaOnly = HomebrewDependencyGraph.display(formulaOnly,
                                                              installed: dependencyPackages,
                                                              groupDependencies: false)
        suite.expect(flatFormulaOnly.rows.count == formulaOnly.count
                     && flatFormulaOnly.rows.allSatisfy { $0.kind == .formula },
                     "Homebrew flat mode keeps the active filter and its displayed count")
        let formulaOnlyFolded = HomebrewDependencyGraph.fold(formulaOnly, installed: dependencyPackages)
        suite.expect(formulaOnlyFolded.rows.map(\.name).contains("cask-lib")
                     && formulaOnlyFolded.orphans.map(\.name) == ["orphan-lib"],
                     "Homebrew shows a cask's dependency as a row, not an orphan, when the filter hides the cask")
        let oldBrewPackages = (try? HomebrewParser.parseInfoJSON(Data(dependencyJSON
            .replacingOccurrences(of: "\"installed_on_request\": true,", with: "")
            .replacingOccurrences(of: "\"installed_on_request\": false,", with: "").utf8))) ?? []
        let oldBrewFolded = HomebrewDependencyGraph.fold(oldBrewPackages, installed: oldBrewPackages)
        suite.expect(oldBrewFolded.rows.count == 8 && oldBrewFolded.dependencies.isEmpty && oldBrewFolded.orphans.isEmpty,
                     "Homebrew keeps the flat list when brew does not report installed_on_request, found \(oldBrewFolded.rows.count)")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.homebrewGroupDependencies] as? Bool == true
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.homebrewGroupDependencies),
                     "Homebrew grouping remains the default and the alternative layout travels with settings backups")
        let searchPackages = HomebrewParser.parseSearchOutput("sample-formula\nbad token\nsample-filter\nsample-tool\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        suite.expect(searchPackages.map(\.name) == ["sample-formula", "sample-filter", "sample-tool"],
               "Homebrew search parser keeps valid one-token results")
        let analyticsJSON = """
        {
          "category": "formula_install_on_request",
          "formulae": {
            "sample-formula": [
              { "formula": "sample-formula", "count": "21,557" },
              { "formula": "sample-formula --HEAD", "count": "30" }
            ],
            "sample-filter": [
              { "formula": "sample-filter", "count": "42,001" }
            ]
          }
        }
        """
        let popularity = (try? HomebrewAnalytics.parse(Data(analyticsJSON.utf8), kind: .formula)) ?? [:]
        suite.expect(popularity["sample-formula"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        suite.expect(popularity["sample-filter"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        suite.expect(rankedPackages.map(\.name) == ["sample-filter", "sample-formula", "sample-tool"],
               "Homebrew search results sort by popularity first")
        suite.expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")
        var newlyInstalled = rankedPackages[0]
        newlyInstalled.installedVersion = "2.0"
        let afterInstall = HomebrewSearchResults.reconciled(rankedPackages, installed: [newlyInstalled])
        suite.expect(afterInstall.first?.isInstalled == true
                     && afterInstall.first?.popularity == rankedPackages.first?.popularity,
                     "Homebrew search shows an installed package without losing its popularity")
        let afterUninstall = HomebrewSearchResults.reconciled(afterInstall, installed: [])
        suite.expect(afterUninstall.first?.isInstalled == false
                     && afterUninstall.map(\.id) == rankedPackages.map(\.id),
                     "Homebrew search returns to an installable result after uninstall")

        // Purgeable space is queried only for writable volumes: the bulk fetch
        // asks nothing that only a writable volume can answer, and a volume
        // that says it is read-only is not asked. The scratch folder's volume
        // answers when it is not called read-only, so the refusal is the
        // sampler's own.
        suite.expect(!DiskSampler.volumeKeys.contains(.volumeAvailableCapacityForImportantUsageKey)
                && DiskSampler.volumeKeys.contains(.volumeIsReadOnlyKey),
               "the bulk volume fetch asks nothing that only a writable volume can answer")
        let writableFolder = FileManager.default.temporaryDirectory
        suite.expect(DiskSampler.importantFree(for: writableFolder, isReadOnly: false) != nil
                && DiskSampler.importantFree(for: writableFolder, isReadOnly: true) == nil,
               "purgeable space is read only where there is something to purge")

        // Only localized fields that reach String(format:) need matching
        // placeholders in every language. bazel/source_lints.py keeps the
        // list equal to the fields the sources hand to String(format:).
        let formatFields = Set(SourceNames.formatFields)
        suite.expect(formatFields.count > 10, "the format fields were found to compare (\(formatFields.count))")
        var mismatched: [String] = []
        for (language, strings) in LocalizationTests.languages where language != .enUS {
            let mine = Mirror(reflecting: strings).children
            let base = Mirror(reflecting: Strings.enUS).children
            for (left, right) in zip(base, mine) {
                guard let label = left.label, formatFields.contains(label),
                      let english = left.value as? String,
                      let other = right.value as? String else { continue }
                if TestFormat.parse(english) == nil
                    || TestFormat.parse(english)?.arguments != TestFormat.parse(other)?.arguments {
                    mismatched.append("\(label)/\(language.rawValue)")
                }
            }
        }
        suite.expect(mismatched.isEmpty,
               "every language fills a format the same way (\(mismatched.prefix(5).joined(separator: ", ")))")

        // Every literal SF Symbol name resolves on the test system.
        // bazel/source_lints.py keeps the list equal to the names the sources
        // spell.
        let symbolNames = Set(SourceNames.symbols)
        suite.expect(symbolNames.count > 80, "the symbol names were found (\(symbolNames.count))")
        var missingSymbols: [String] = []
        for name in symbolNames.sorted()
        where NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            missingSymbols.append(name)
        }
        suite.expect(missingSymbols.isEmpty,
               "every symbol the app draws exists (\(missingSymbols.joined(separator: ", ")))")

        // Absolute command-line tool paths embedded in Swift must exist.
        // bazel/source_lints.py keeps the list equal to the paths the sources
        // spell.
        let toolPaths = Set(SourceNames.systemTools)
        suite.expect(toolPaths.count >= 15, "the system tools were found (\(toolPaths.count))")
        let missingTools = toolPaths.sorted().filter {
            !FileManager.default.fileExists(atPath: $0)
        }
        suite.expect(missingTools.isEmpty,
               "every system tool the app runs is where it expects (\(missingTools.joined(separator: ", ")))")

        // MARK: Tools/setup-signing.sh runs end to end against the stock openssl
        // The setup script must run against the stock /usr/bin/openssl, which
        // is LibreSSL: it rejects OpenSSL 3's -legacy flag outright, and the
        // script once died on exactly that with its stderr discarded. It runs
        // here against that openssl, in a scratch home, with stand-ins for
        // security(1) and codesign that log what they are asked and touch no
        // keychain. The codesign stand-in refuses until the identity has been
        // imported, as codesign does before the script has made one.
        let signingScratch = scratchFolder("signing-setup")
        defer { try? FileManager.default.removeItem(at: signingScratch) }
        let signingStubs = signingScratch.appendingPathComponent("bin")
        let signingHome = signingScratch.appendingPathComponent("home").path
        let signingTemp = signingScratch.appendingPathComponent("tmp").path
        let signingLog = signingScratch.appendingPathComponent("calls.log").path
        let logCall = #"{ printf '%s' "${0##*/}"; printf '|%s' "$@"; printf '\n'; } >> "$STUB_LOG""#
        let signingStaged = [
            writeStub("security", in: signingStubs, logCall + "\n" + #"""
                [ "$1" = import ] && : > "$STUB_STATE/imported"
                [ "$1" = list-keychains ] && [ "$#" -eq 3 ] && echo '    "/stub/login.keychain-db"'
                exit 0
                """#),
            writeStub("codesign", in: signingStubs, logCall + "\n" + #"""
                for last; do :; done
                cmp -s "$last" /bin/echo && echo "probe is a copy of /bin/echo" >> "$STUB_LOG"
                [ -e "$STUB_STATE/imported" ]
                """#),
            writeStub("openssl", in: signingStubs, logCall + "\n" + #"exec /usr/bin/openssl "$@""#),
            (try? FileManager.default.createDirectory(atPath: signingHome, withIntermediateDirectories: true)) != nil,
            (try? FileManager.default.createDirectory(atPath: signingTemp, withIntermediateDirectories: true)) != nil,
        ].allSatisfy { $0 }
        let signingSetup = BoundedProcessRunner.run(
            "/bin/zsh", ["Tools/setup-signing.sh"], timeout: 60, maxOutputBytes: 16_384,
            environment: ["HOME": signingHome, "TMPDIR": signingTemp, "PATH": signingStubs.path + ":/usr/bin:/bin",
                          "STUB_LOG": signingLog, "STUB_STATE": signingScratch.path])
        let signingCalls = ((try? String(contentsOf: URL(fileURLWithPath: signingLog), encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
        suite.expect(signingStaged && signingSetup.status == 0
                && signingCalls.contains { $0.hasPrefix("openssl|pkcs12|-export|") },
               "setup-signing.sh makes its identity with the stock LibreSSL openssl: "
               + String(decoding: signingSetup.output, as: UTF8.self))
        suite.expect(signingCalls.contains { $0.hasPrefix("openssl|") }
                && !signingCalls.contains { $0.hasPrefix("openssl|") && $0.contains("|-legacy") },
               "setup-signing.sh avoids the -legacy flag the stock LibreSSL openssl rejects")
        suite.expect(signingCalls.contains { $0.hasPrefix("security|import|") }
                && !signingCalls.contains { $0.contains("find-identity") },
               "Tools/setup-signing.sh never decides the stable identity by a find-identity listing")
        suite.expect(signingCalls.contains { $0.hasPrefix("codesign|") && $0.contains("|--sign|Vitruvian Signing|") }
                && signingCalls.contains("probe is a copy of /bin/echo"),
               "Tools/setup-signing.sh asks codesign to sign a throwaway copy of /bin/echo with the stable identity")
        let signingLeftovers = (try? FileManager.default.contentsOfDirectory(atPath: signingTemp)) ?? ["<unreadable>"]
        suite.expect(signingLeftovers.isEmpty,
               "setup-signing.sh removes its probe and its work folder: \(signingLeftovers)")

        // MARK: Uninstallation paths stay aligned across SelfUninstall and Tools/uninstall.sh
        // Neither query learning nor uninstall touches Keychain, which
        // bazel/source_lints.py checks; what the bar learns is never stored.
        queryHabitsStayInMemory(suite)
        // The script's own steps run here over scratch folders, against what
        // the app removes and looks for. First the files: everything the
        // in-app uninstall removes is staged in a scratch home, beside the
        // Developer build's files and another app's, which must stay.
        let uninstallScratch = scratchFolder("uninstall")
        defer { try? FileManager.default.removeItem(at: uninstallScratch) }
        let uninstallHome = uninstallScratch.appendingPathComponent("home").path
        let releaseBundleID = "com.vitruviansoftware.vitruvian"
        let appRemoves = SelfUninstall.ownedPaths(home: uninstallHome, bundleID: releaseBundleID)
        let byHostPreferences = "\(uninstallHome)/Library/Preferences/ByHost/\(releaseBundleID).0123-ABCD.plist"
        let notTheApp = [
            "\(uninstallHome)/Library/Application Support/\(releaseBundleID).dev",
            "\(uninstallHome)/Library/Preferences/\(releaseBundleID).dev.plist",
            "\(uninstallHome)/Library/Caches/com.example.other",
            "\(uninstallHome)/Library/Preferences/ByHost/com.example.other.0123-ABCD.plist",
        ]
        let uninstallStaged = (appRemoves + [byHostPreferences] + notTheApp).allSatisfy { path in
            ["plist", "binarycookies"].contains((path as NSString).pathExtension)
                ? stageScratchFile(path) : stageScratchFile(path + "/contents")
        }
        let userStateRemoval = BoundedProcessRunner.run(
            "/bin/zsh",
            ["-c", #"source <(sed -n '/^remove_user_state() {$/,/^}$/p' Tools/uninstall.sh) && remove_user_state "$1" "$2""#,
             "zsh", uninstallHome, releaseBundleID],
            timeout: 10, maxOutputBytes: 4_096)
        let scriptKept = appRemoves.filter { FileManager.default.fileExists(atPath: $0) }
        suite.expect(uninstallStaged && userStateRemoval.status == 0 && scriptKept.isEmpty,
               "script uninstall removes everything the in-app uninstall removes, kept \(scriptKept)")
        let requiredSubpaths = ["Library/Application Support", "Library/Caches", "Library/HTTPStorages"]
        for subpath in requiredSubpaths {
            let underSubpath = appRemoves.filter { $0.hasPrefix("\(uninstallHome)/\(subpath)/") }
            suite.expect(uninstallStaged && !underSubpath.isEmpty
                    && !underSubpath.contains { FileManager.default.fileExists(atPath: $0) },
                   "both in-app and script uninstall sweep \(subpath)")
        }
        suite.expect(uninstallStaged && !FileManager.default.fileExists(atPath: byHostPreferences),
               "script uninstall sweeps ByHost preferences")
        suite.expect(notTheApp.allSatisfy { FileManager.default.fileExists(atPath: $0) },
               "script uninstall leaves the Developer build's files and other apps' alone")
        // zsh passes a plain string to a command as one word, so the script
        // checks each closed-lid rule name on its own. With every file the app
        // looks for in place under a scratch root, under the current name and
        // every earlier one, the script has to find each of them.
        let rulesRoot = uninstallScratch.appendingPathComponent("root").path
        let rulesStaged = Sudoers.ruleFiles.allSatisfy { stageScratchFile(rulesRoot + $0) }
        let rulesSearch = BoundedProcessRunner.run(
            "/bin/zsh",
            ["-c", #"source <(sed -n '/^find_closed_lid_rules() {$/,/^}$/p' Tools/uninstall.sh); find_closed_lid_rules "$1"; print -rl -- $found_rules"#,
             "zsh", rulesRoot],
            timeout: 10, maxOutputBytes: 4_096)
        let scriptRuleFiles = Set(String(decoding: rulesSearch.output, as: UTF8.self)
            .split(separator: "\n").map(String.init))
        suite.expect(rulesStaged && !Sudoers.ruleFiles.isEmpty && scriptRuleFiles == Set(Sudoers.ruleFiles),
               "script uninstall looks for the same closed-lid rule files as the app: \(scriptRuleFiles.sorted())")
        // Restoring sleep used to be fired and forgotten at both exits. A
        // failure there leaves `pmset disablesleep 1` set system-wide, and
        // removal deletes the flag that launch-time recovery reads before it
        // reads the setting, so nothing repairs it afterwards — a reinstall
        // included. The flows run through injected steps, and
        // SelfUninstallTests checks that a failed sleep restore or fan detach
        // stops them; the system's steps are the real restores.
        uninstallStepsAreTheRealOnes(suite)
        // The real sleep restore reports success only when sleep was never the
        // app's to restore, or is known to be back: a flag that outlived the
        // setting asks for no password, a probe that did not answer says
        // nothing, and after the password only a reading that sleep is on
        // again counts.
        typealias PmsetReading = (status: Int32, output: String)
        let sleepOff: PmsetReading = (0, "System-wide power settings:\n SleepDisabled\t\t1\n")
        let sleepOn: PmsetReading = (0, "System-wide power settings:\n SleepDisabled\t\t0\n")
        let noAnswer: PmsetReading = (1, "")
        func sleepRestore(flagged: Bool = true, readings: [PmsetReading],
                          rule: Bool = false, password: Bool = false) -> String {
            var pending = readings
            var steps: [String] = []
            let restored = SelfUninstall.restoreSleep(
                flagged: flagged,
                probe: {
                    steps.append("probe")
                    return pending.isEmpty ? noAnswer : pending.removeFirst()
                },
                restoreWithoutPassword: { steps.append("rule"); return rule },
                restoreAsAdministrator: { steps.append("password"); return password })
            return (restored ? "restored" : "kept") + ": " + steps.joined(separator: ", ")
        }
        let sleepRestores = [
            sleepRestore(flagged: false, readings: [sleepOff]),
            sleepRestore(readings: [sleepOn]),
            sleepRestore(readings: [noAnswer], rule: true),
            sleepRestore(readings: [sleepOff], rule: true),
            sleepRestore(readings: [sleepOff]),
            sleepRestore(readings: [sleepOff, sleepOn], password: true),
            sleepRestore(readings: [sleepOff, sleepOff], password: true),
            sleepRestore(readings: [noAnswer, noAnswer], password: true),
        ]
        suite.expect(sleepRestores == [
            "restored: ",
            "restored: probe",
            "restored: probe, rule",
            "restored: probe, rule",
            "kept: probe, rule, password",
            "restored: probe, rule, password, probe",
            "kept: probe, rule, password, probe",
            "kept: probe, rule, password, probe",
        ], "in-app uninstall restores normal sleep before removal, or stops: \(sleepRestores)")
        // The script reads the sleep setting back for itself, from what pmset
        // reports, and reads it as the app does. A stand-in pmset gives the
        // report; when it does not answer, the script reads nothing, which it
        // must not take for sleep restored.
        let pmsetStubs = uninstallScratch.appendingPathComponent("bin")
        let pmsetReport = uninstallScratch.appendingPathComponent("pmset-report").path
        let pmsetStubWritten = writeStub("pmset", in: pmsetStubs, #"cat "$PMSET_REPORT""#)
        for setting in ["1", "0", nil] as [String?] {
            let report = setting.map {
                "System-wide power settings:\n SleepDisabled\t\t\($0)\nCurrently in use:\n standby              1\n"
            }
            try? FileManager.default.removeItem(atPath: pmsetReport)
            let reported = report.map { (try? $0.write(toFile: pmsetReport, atomically: true, encoding: .utf8)) != nil } ?? true
            let sleepRead = BoundedProcessRunner.run(
                "/bin/zsh",
                ["-c", #"source <(sed -n '/^read_sleep_disabled() {$/,/^}$/p' Tools/uninstall.sh) && read_sleep_disabled"#],
                timeout: 10, maxOutputBytes: 1_024,
                environment: ["PATH": pmsetStubs.path + ":/usr/bin:/bin", "PMSET_REPORT": pmsetReport])
            let scriptReads = String(decoding: sleepRead.output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let appAgrees = report.map { SudoersSupport.sleepDisabled(inPmsetOutput: $0) == (setting == "1") } ?? true
            suite.expect(pmsetStubWritten && reported && scriptReads == (setting ?? "") && appAgrees,
                   "script uninstall reads the sleep setting back for itself, as the app does "
                   + "(reported \(setting ?? "nothing"), read \(scriptReads.isEmpty ? "nothing" : scriptReads))")
        }
        brightnessTeardownKeepsTheDisplays(suite)

        // MARK: Secure input

        suite.expect(SecureInputSupport.holder(isEnabled: false,
                                         read: .noHolder,
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .off,
               "secure input off with no recorded holder is off")
        var secureInputNameLookups = 0
        let secureInputOffWithPid = SecureInputSupport.holder(
            isEnabled: false,
            read: .holder(4242),
            runningApp: { pid in
                secureInputNameLookups += 1
                return ("SomeBrowser", pid)
            },
            isProcessAlive: { _ in true })
        suite.expect(secureInputOffWithPid == .off,
               "secure input off stays off even with a pid still recorded")
        suite.expect(SecureInputSupport.holder(isEnabled: false,
                                         read: .unavailable,
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .off,
               "secure input off stays off when the session cannot be read")
        suite.expect(secureInputNameLookups == 0,
               "the name lookup is skipped when secure input is off")

        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(999),
                                         runningApp: { pid in
                                             pid == 999 ? ("SomeBrowser", 4242) : nil
                                         },
                                         isProcessAlive: { _ in true })
                   == .app(name: "SomeBrowser", pid: 4242),
               "a helper pid is attributed to the app responsible for it")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(4242),
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .unknown,
               "a running holder that is no regular app is never sent to log out")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(4242),
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in false }) == .unattributed,
               "a holder that has exited is what a new login session clears")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .noHolder,
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .unattributed,
               "secure input on with no recorded holder is unattributed")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(0),
                                         runningApp: { pid in ("SomeBrowser", pid) },
                                         isProcessAlive: { _ in true }) == .unattributed,
               "a zero pid is not an attribution")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(4242),
                                         runningApp: { pid in ("", pid) },
                                         isProcessAlive: { _ in false }) == .unattributed,
               "an empty app name is not an attribution")

        var secureInputUnavailableLookups = 0
        var secureInputUnavailableLivenessChecks = 0
        let secureInputUnavailable = SecureInputSupport.holder(
            isEnabled: true,
            read: .unavailable,
            runningApp: { pid in
                secureInputUnavailableLookups += 1
                return ("SomeBrowser", pid)
            },
            isProcessAlive: { _ in
                secureInputUnavailableLivenessChecks += 1
                return true
            })
        suite.expect(secureInputUnavailable == .unknown,
               "a session that cannot be read reports an unknown holder")
        suite.expect(secureInputUnavailableLookups == 0 && secureInputUnavailableLivenessChecks == 0,
               "a session that cannot be read costs no name lookup and no liveness check")

        suite.expect(!SecureInputSupport.shouldPoll(observingSurfaceCount: 0, windowIsOpen: true),
               "secure input keeps no timer without a visible surface")
        suite.expect(SecureInputSupport.shouldPoll(observingSurfaceCount: 1, windowIsOpen: true)
                   && SecureInputSupport.shouldPoll(observingSurfaceCount: 3, windowIsOpen: true),
               "a visible surface polls secure input while the window is open")
        suite.expect(SecureInputSupport.shouldPoll(observingSurfaceCount: 1, windowIsOpen: true)
                   == SecureInputSupport.shouldPoll(observingSurfaceCount: 2, windowIsOpen: true),
               "repeating a demand does not change whether secure input polls")
        suite.expect(!SecureInputSupport.shouldPoll(observingSurfaceCount: 1, windowIsOpen: false),
               "a demand left over from before the window closed does not poll on its own")
        suite.expect(!SecureInputSupport.shouldPoll(observingSurfaceCount: 0, windowIsOpen: false),
               "neither gate alone is enough")

    }
}
