#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Verify that selected real regressions fail their existing tests.

Each mutation is applied to the checkout, the unit tests run through Bazel,
and the file is put back. The mutation must fail an assertion with the
expected diagnostic. Compiler errors, timeouts and unrelated failures do not
count as detection.

Run it on macOS (CI runs it weekly):

    bazel run --config=macos-app //apps/desktop/vitruvian:mutation_checks

Arguments after `--` are passed on to each `bazel test`, such as cache flags.
The mutated files must have no uncommitted changes, so that whatever stops a
run, `git checkout` puts them back.
"""
from pathlib import Path
import os
import signal
import subprocess
import sys

# `bazel run` starts this from the runfiles; the checkout is where Bazel was run.
WORKSPACE = Path(os.environ.get("BUILD_WORKSPACE_DIRECTORY") or Path(__file__).resolve().parents[4])
ROOT = WORKSPACE / "apps/desktop/vitruvian"
UNIT_TESTS = "//apps/desktop/vitruvian:unit_tests"

MUTATIONS = [
    ("compact rail eagerly builds history", "notch", "Sources/Vitruvian/UI/Notch/NotchComponents.swift",
     "                    LazyHStack(alignment: .top, spacing: spacing) {",
     "                    HStack(alignment: .top, spacing: spacing) {",
     "a thousand history entries create only the visible rail neighborhood"),
    ("preview recreates the scratchpad editor", "notch", "Sources/Vitruvian/UI/Notch/NotchScratchpadView.swift",
     "                        .opacity(pad.isPreviewing ? 0 : 1)",
     "                        .id(pad.isPreviewing)\n                        .opacity(pad.isPreviewing ? 0 : 1)",
     "preview preserves the same editor and undo history"),
    ("floating scratchpad takes another host's focus", "notch", "Sources/Vitruvian/Services/QuickTools/ScratchpadFocus.swift",
     "guard let window, window.isVisible, !requiresKeyWindow || window.isKeyWindow else { return }",
     "guard let window, window.isVisible else { return }",
     "document actions preserve island focus with the floating host visible or hidden"),
    ("emoji family offers unsupported tones", "emoji", "Sources/Vitruvian/Services/CommandBar/CommandBarEmoji.swift",
     "scalar.value != 0x1F46A && scalar.properties.isEmojiModifierBase", "scalar.properties.isEmojiModifierBase",
     "family stays unchanged instead of offering unsupported skin tones"),
    ("one-off emoji skips usage learning", "emoji", "Sources/Vitruvian/Services/CommandBar/CommandBarRunRecorder.swift",
     "                self.record(entry)\n", "",
     "a one-off tone records exactly one use under the original emoji"),
    ("one-off emoji learns the action field instead of its search", "emoji", "Sources/Vitruvian/Services/CommandBar/CommandBarRunRecorder.swift",
     "        case .argument, .actions:\n", "        case .argument:\n",
     "a one-off tone learns the search saved before opening actions"),
    ("output switches reuse another device's volume baseline", "notch", "Sources/Vitruvian/Services/Notch/NotchVolumeFeedback.swift",
     "                self.volumeBaseline = nil\n                self.muteBaseline = nil\n", "",
     "switching output never replaces its connection notice with stored volume or mute"),
    ("volume observation reads partially published controls", "notch", "Sources/Vitruvian/Services/Notch/NotchVolumeFeedback.swift",
     ".receive(on: DispatchQueue.main)\n            .sink { [weak self] _ in",
     ".sink { [weak self] _ in",
     "switching output never replaces its connection notice with stored volume or mute"),
    ("device alerts return to the fixed level width", "notch", "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "return min(maximum, max(NotchNoticeLayout.minimumWing, ceil(max(leading + symbol, trailing)) + NotchNoticeLayout.inset + cameraGap))",
     "return 112",
     "power labels and connection status fit beside their icon"),
    ("device alert window ignores its content width", "notch", "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "guard noticeExpanded else { return geometry.noticeSize(wingWidth: notice.preferredWingWidth) }",
     "guard noticeExpanded else { return geometry.notice }",
     "a device notice widens the actual presentation beyond the compact level indicator"),
    ("Nothing loses its music gate", "notch", "Sources/Vitruvian/Core/Notch/NotchSupport.swift",
     "            && idleContent(in: defaults) != .none\n", "",
     "selecting Nothing retracts already visible music and stops its reader with cached playback still present"),
    ("resting music bypasses automatic opt-out", "notch", "Sources/Vitruvian/Core/Notch/NotchSupport.swift",
     "return choice == .music && !showsMusicActivity(isPlaying: isPlaying, in: defaults) ? .none : choice",
     "return choice == .music && !isPlaying ? .none : choice",
     "disabled automatic music stops the reader even when resting content is Music"),
    ("resting music retains a disabled reader", "notch", "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "            || (!hiddenUntilHover && (NotchSupport.watchesMusicActivity(in: defaults) || NotchSupport.routes(.track, in: defaults))))",
     "            || (!hiddenUntilHover && (NotchSupport.idleContent(in: defaults) == .music"
     " || NotchSupport.watchesMusicActivity(in: defaults) || NotchSupport.routes(.track, in: defaults))))",
     "disabled automatic music stops the reader even when resting content is Music"),
    ("closing music retains its on-demand reader", "notch", "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "        removeEventMonitors()\n        syncVisibleConsumers()\n        closeCapture?()\n    }\n\n    package func toggle()",
     "        removeEventMonitors()\n        closeCapture?()\n    }\n\n    package func toggle()",
     "closing manually opened controls stops the reader and never leaves a music strip behind"),
    ("the software route keeps the picture dimmed when it is turned off", "software-dimming",
     "Sources/Vitruvian/Services/Display/BrightnessService.swift",
     "        guard !preferred else {\n"
     "            refresh(force: true)\n"
     "            return\n"
     "        }\n"
     "        // Handing the display back to DDC has to hand the picture back with\n"
     "        // it. The scaled curve belongs to this app, and the level behind it\n"
     "        // describes the gamma route, not the monitor: left in place they show\n"
     "        // a dark screen the monitor's own controls cannot explain, and the\n"
     "        // first write to the panel then dims what is already dimmed. The\n"
     "        // curve goes back before the rebuild, so the probe reads a display\n"
     "        // showing its own picture.\n"
     "        stateLock.lock()\n"
     "        lastApplied[id] = nil\n"
     "        levelKnownAt[id] = nil\n"
     "        stateLock.unlock()\n"
     "        environment.work { [weak self] in\n"
     "            guard let self else { return }\n"
     "            self.applySoftwareDim(id, value: 1)\n"
     "            self.environment.main { [weak self] in self?.refresh(force: true) }\n"
     "        }\n",
     "        refresh(force: true)\n",
     "the picture goes back to its own curve when the choice goes off"),
    ("a timed session hands over on one condition", "keep-awake", "Sources/Vitruvian/Services/KeepAwakeManager.swift",
     "        guard KeepAwakeAutomationSupport.conditionsSatisfied(\n"
     "                matching: matches,\n"
     "                enabled: enabled(),\n"
     "                requireAll: requireAll()) else { return nil }\n",
     "        guard !matches.isEmpty else { return nil }\n",
     "a timer running out on battery hands nothing over to an All automation"),
    ("lid sleep ignores a display connection in progress", "keep-awake", "Sources/Vitruvian/Core/KeepAwakeAutomationSupport.swift",
     'return appliesToLid && assertion["AssertLevel"] as? Int != 0', 'return false',
     "a live monitor transition overrides a stale allowed lid policy"),
    ("lid sleep forgets to retry a refusal", "keep-awake", "Sources/Vitruvian/Services/KeepAwakeManager.swift",
     "guard result != kIOReturnSuccess, attemptsLeft > 1 else { return }",
     "guard false else { return }",
     "a refused lid sleep retries until the system accepts it"),
    ("match mode labels grow back into sentences", "preferences", "Sources/Vitruvian/Core/KeepAwakeStrings.swift",
     "        matchAny: \"L\u2019une\",\n        matchAll: \"Toutes\",\n",
     "        matchAny: \"N\u2019importe quelle condition\",\n        matchAll: \"Toutes les conditions\",\n",
     "fr: the match mode labels fit the panel card"),
    ("recording metadata rebases after startup", "recording", "Sources/Vitruvian/Core/Recorder/RecorderSupport.swift",
     "return timeline.eventTime(time, since: origin)",
     "return timeline.eventTime(time, since: origin + 0.3)",
     "stored pointer, click and typing markers align with decoded video after delayed startup and pauses"),
    ("microphone returns to its changing native format", "recording", "Sources/Vitruvian/Services/Recorder/RecorderWriter.swift",
     "let interleaved = Self.interleavedAudioSample(sampleBuffer, converter: &microphoneConverter)",
     "let interleaved = Optional(sampleBuffer)",
     "writer dropped required microphone fixture sample"),
    ("system audio returns to its changing native format", "recording", "Sources/Vitruvian/Services/Recorder/RecorderWriter.swift",
     "let interleaved = Self.interleavedAudioSample(sampleBuffer, converter: &systemAudioConverter)",
     "let interleaved = Optional(sampleBuffer)",
     "writer dropped required systemAudio fixture sample"),
    ("missing feed loses fallback requirement", "app-updates", "Sources/Vitruvian/Core/AppUpdates/AppUpdateFeedSupport.swift",
     "return Findings(catalogFallbackPaths: Set(apps.map(\\.path)))", "return Findings()",
     "manifest 404 missing: only usable catalog coverage clears a missing-feed warning"),
    ("current catalog app loses coverage", "app-updates", "Sources/Vitruvian/Core/AppUpdates/AppUpdatesSupport.swift",
     "if !isUncomparable(app.version) { checkedPaths.insert(app.path) }",
     "if isNewer(versionCore(entry.version), than: app.version) { checkedPaths.insert(app.path) }",
     "manifest 404 current: only usable catalog coverage clears a missing-feed warning"),
    ("ambiguous catalog claims coverage", "app-updates", "Sources/Vitruvian/Core/AppUpdates/AppUpdatesSupport.swift",
     "guard matches.count == 1, let entry = matches.first else { return nil }",
     "guard !matches.isEmpty, let entry = matches.first else { return nil }",
     "manifest 404 ambiguous: only usable catalog coverage clears a missing-feed warning"),
    ("switcher ignores resized viewport", "switcher", "Sources/Vitruvian/UI/Switcher/SwitcherWindowStrip.swift",
     "            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { _ in\n"
     "                DispatchQueue.main.async {\n"
     "                    revealSelection(in: proxy, animated: false)\n"
     "                }\n"
     "            }",
     "",
     "previews search/narrowed without changing selection"),
    ("paused silence writes off the resumed play", "notch", "Sources/Vitruvian/Services/Notch/NotchAudioLevelService.swift",
     "        if stopWork == nil { silence.giveUp(on: identity) }",
     "        silence.giveUp(on: identity)",
     "silence heard during the pause grace does not write the next play off"),
    ("resumed play keeps a reader still reporting paused silence", "notch", "Sources/Vitruvian/Services/Notch/NotchAudioLevelService.swift",
     "        guard readerPID != pid || resumeBeforeSound else { return }",
     "        guard readerPID != pid else { return }",
     "a delayed silence report from the pause cannot write off the resumed play"),
    ("switcher loses replacement identity", "switcher", "Sources/Vitruvian/UI/Switcher/SwitcherWindowStrip.swift",
     "            .onChange(of: windows.map(\\.element.id)) { _, _ in",
     "            .onChange(of: windows.count) { _, _ in",
     "previews boundary close/next app at unchanged index"),
    ("switcher follows window count", "switcher-model", "Sources/Vitruvian/Core/Switcher/SwitcherSupport.swift",
     ": min(2, max(windowCount, maximumWindowCount))",
     ": min(2, windowCount)",
     "App Switcher keeps short icon rows stationary when changing apps"),
    ("invalid numeric result", "harness", "Tests/TestSuite.swift",
     "actual.isFinite && expected.isFinite && tol.isFinite && tol >= 0\n                   && abs(actual - expected) <= tol",
     "!(abs(actual - expected) > tol)", "every invalid numeric comparison fails"),
    ("invalid saved zoom", "screenshots", "Sources/Vitruvian/Core/QuickTools/ScreenshotSupport.swift",
     "guard requested.isFinite else { return 1 }", "guard requested.isFinite else { return requested }",
     "an invalid saved magnifier zoom falls back safely"),
    ("recording starts before the launcher hides", "launcher", "Sources/Vitruvian/Services/QuickTools/QuickLauncherService.swift",
     "        case .keepAwake, .micMute:\n            environment.perform(item)\n"
     "        case .screenOCR, .screenshot, .screenRecorder, .colorPicker, .scratchpad:",
     "        case .keepAwake, .micMute, .screenRecorder:\n            environment.perform(item)\n"
     "        case .screenOCR, .screenshot, .colorPicker, .scratchpad:",
     "screenRecorder executes the intended action exactly once"),
    ("incorrect recording icon", "launcher", "Sources/Vitruvian/UI/QuickLauncher/QuickLauncherView.swift",
     'case .screenRecorder: return state.recording ? "stop.circle" : "record.circle"',
     'case .screenRecorder: return "record.circle"', "an active recording tile offers stopping"),
    ("missing translation", "localization", "Sources/Vitruvian/Core/FeatureStrings.swift",
     'shortcutHint: "Clique numa linha para colar no app anterior. ⌘+clique seleciona várias; ⌘C copia sem colar."',
     'shortcutHint: ""', "clipboard/pt-BR: missing text in shortcutHint"),
    ("unsafe argument comparison", "harness", "Tests/LocalizationTests.swift",
     "actual?.arguments == expected?.arguments",
     "actual?.arguments.values.sorted() == expected?.arguments.values.sorted()",
     "localization validation detects missing text and unsafe argument swaps"),
    ("unreachable window visibility preference", "screenshots",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotCapturePolicy.swift",
     "        honoursVisibilityPreference\n            ? workflowWindowIDs\n            : workflowWindowIDs.union(contentWindowIDs)",
     "        workflowWindowIDs.union(contentWindowIDs)",
     "a screenshot protects only the surfaces taking it"),
    ("tool switch keeps a stale picture of own windows", "screenshots",
     "Sources/Vitruvian/Core/QuickTools/ScreenshotSupport.swift",
     "                && hideVitruvianWindows == other.hideVitruvianWindows\n                && keepsContentWindowsOut == other.keepsContentWindowsOut",
     "                && hideVitruvianWindows == other.hideVitruvianWindows",
     "switching between recording and screenshot, text or color refreshes the picture and pickable windows both ways"),
    ("capture accepts a refreshing source", "capture",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "        sourceRefreshPending = true", "        sourceRefreshPending = false",
     "pending refresh rejects region, window, full-screen, repeat and color confirmations"),
    ("capture reuses a failed display", "capture",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "guard !freeze || panels.allSatisfy({ frozenImages[$0.displayID] != nil }) else",
     "guard true else",
     "missing refreshed display closes selection safely"),
    ("old loupe overwrites the selected tool", "capture",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "guard let self, !self.finished, self.sourceGeneration == generation else",
     "guard let self, !self.finished else",
     "a previous tool's delayed live loupe cannot replace the current source"),
    ("full-screen action loses its first click", "screenshots",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "        acceptsFirstClick = true", "        acceptsFirstClick = false",
     "the interactive full-screen host receives its first click while Dynamic Island owns key focus"),
    ("full-screen hover highlights the window underneath", "capture",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "                && !pointerIsOverFullScreenControl(point)",
     "                && true",
     "hovering the full-screen action suppresses the window capture highlight"),
    ("island collapse moves a hovered full-screen action", "capture",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "        if fullScreenControlHovered {", "        if false {",
     "an island collapse cannot move the full-screen action while it is hovered"),
    ("hidden full-screen action keeps stale hover", "capture",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift",
     "        if hidden { resetFullScreenControlHover() }",
     "        if false { resetFullScreenControlHover() }",
     "hiding a hovered full-screen action clears hover and applies deferred island geometry"),
    ("lowered capsule overlaps the full-screen action", "notch",
     "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "            geometry.screen, geometry.floatingDrop + size.height)",
     "            geometry.screen, size.height)",
     "a lowered capsule publishes its drop plus height so it cannot cover the full-screen action"),
    ("full-screen action appears on every display", "screenshots",
     "Sources/Vitruvian/Core/QuickTools/ScreenshotSupport.swift",
     "        isAvailable && pointerOnDisplay && !selectionInProgress && !capturePending",
     "        isAvailable && !selectionInProgress && !capturePending",
     "the full-screen action stays on the pointer display and disappears as soon as selection or capture starts"),
    ("overwrite unreadable notes", "storage", "Sources/Vitruvian/Services/QuickTools/ScratchpadStore.swift",
     "        guard canSave else { return false }", "        // guard canSave else { return false }",
     "damaged scratchpad blocks subsequent saves of empty and nonempty documents"),
    ("island forgets a preview stays until dismissed", "notch", "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "        captureClosesOnCollapse = closeOnCollapse\n", "",
     "capture controls detach a persistent preview before closing it after island takeover"),
    ("confirmation switch stops hiding previews", "screenshots",
     "Sources/Vitruvian/Core/QuickTools/ScreenshotSupport.swift",
     "confirmationEnabled: defaults[Preferences.screenshotPreviewEnabled])",
     "confirmationEnabled: true)",
     "with confirmations off a successful action shows nothing"),
    ("upload shortcut publishes an edited capture's original", "screenshots",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotLatestCapture.swift",
     "        withhold()\n        editors.append(editor)",
     "        editors.append(editor)",
     "a capture that went through an editor is not published"),
    ("island link click publishes at once", "screenshots",
     "Sources/Vitruvian/Services/QuickTools/ScreenshotQuickPreviewController.swift",
     "        embedded ? .opensDurations : .sharesSavedLink\n",
     "        .sharesSavedLink\n",
     "the island's link button opens the durations on a click"),
    ("clipboard highlight searches the whole preview", "clipboard",
     "Sources/Vitruvian/Services/Clipboard/ClipboardHistorySupport.swift",
     "        let visible = excerpt(string)\n",
     "        let visible = string\n",
     "a long preview is searched and styled only as far as a row can show"),
    ("clipboard highlight restyles the whole row", "clipboard",
     "Sources/Vitruvian/Services/Clipboard/ClipboardHistorySupport.swift",
     "        var attributed = AttributedString(visible)\n",
     "        var attributed = AttributedString(visible)\n        attributed.foregroundColor = .primary\n",
     "a highlighted row styles only its matches and leaves the rest to its text's modifiers"),
    ("agent log written again in place goes unnoticed", "agents",
     "Sources/Vitruvian/Services/AgentUsage/AgentUsageStore.swift",
     "        if identity != cursor.identity || size < cursor.offset\n"
     "            || (size > cursor.offset && !cursor.holdsWhatWasRead) {\n",
     "        if identity != cursor.identity || size < cursor.offset {\n",
     "a log written again in place while the app runs is read again at once"),
    ("agent progress keeps a log that started over", "agents",
     "Sources/Vitruvian/Services/AgentUsage/AgentUsageService.swift",
     "let kept = cursors.values.filter { !$0.restarted && $0.provider != .opencode }",
     "let kept = cursors.values.filter { $0.provider != .opencode }",
     "a log replaced or written again while the app ran is left out of saved progress"),
    ("a copy covers the island's own display", "notch", "Sources/Vitruvian/Services/Notch/NotchMirrors.swift",
     "if id != island.displayID, !hidesAtRest, !fullscreenDisplays.contains(id),",
     "if !hidesAtRest, !fullscreenDisplays.contains(id),",
     "every display but the island's own shows a copy, at once"),
    ("closing the copies leaves their windows open", "notch", "Sources/Vitruvian/Services/Notch/NotchMirrors.swift",
     "        copies.values.forEach { $0.host.close() }\n",
     "",
     "choosing one display closes every copy"),
    ("edge-click refresh stacks monitors", "notch", "Sources/Vitruvian/Services/Notch/NotchScreenEdgeClicks.swift",
     "        guard monitors.isEmpty else { return }\n",
     "",
     "refreshes keep exactly one pair of edge-click monitors"),
    ("a drag off the island keeps the edge click", "notch", "Sources/Vitruvian/Services/Notch/NotchScreenEdgeClicks.swift",
     "                  !(pressArea.map { NotchSupport.screenEdgeArea($0, contains: point) } ?? false) else { return }\n            pressArea = nil\n",
     "                  !(pressArea.map { NotchSupport.screenEdgeArea($0, contains: point) } ?? false) else { return }\n",
     "dragging off the island or releasing outside cancels an edge click"),
    ("the island moves under Mission Control", "notch", "Sources/Vitruvian/Services/Notch/NotchPointerFollower.swift",
     "island.canFollow(), !island.isConcealedForMissionControl(),",
     "island.canFollow(),",
     "the island waits for Mission Control to end before it moves"),
    ("each pointer move schedules its own follow", "notch", "Sources/Vitruvian/Services/Notch/NotchPointerFollower.swift",
     "        guard cancelPending == nil, island.canFollow() else { return }",
     "        guard island.canFollow() else { return }",
     "a burst of moves on another display waits once"),
    ("a movement watch stacks monitors", "notch", "Sources/Vitruvian/Services/Notch/NotchMovementWatch.swift",
     "        guard monitors.isEmpty else { return }\n",
     "",
     "hidden mode keeps one pair of native movement observers"),
    ("a short strip keeps full-size agent marks", "agents", "Sources/Vitruvian/Core/Notch/NotchAgentSupport.swift",
     "        min(working > 1 ? 11 : 14, max(8, height - NotchLayout.compactEdgeGap * 2 - 4))\n",
     "        working > 1 ? 11 : 14\n",
     "a short strip shrinks its agent marks to fit between its edge gaps"),
    ("a media target change goes unannounced", "shelf", "Sources/Vitruvian/Services/Notch/NotchFileDrop.swift",
     "    package private(set) var targetsMedia = false {\n        willSet { island.willChange() }\n    }\n",
     "    package private(set) var targetsMedia = false\n",
     "the island announces each change of the drop's destinations, and only a change"),
    ("capture teardown keeps its movement watch", "notch", "Sources/Vitruvian/Services/Notch/NotchService.swift",
     "    private func removeCaptureControlsClickThrough() {\n        captureControlsWatch.stop()\n",
     "    private func removeCaptureControlsClickThrough() {\n",
     "capture teardown leaves no scheduled work or capture monitors"),
    ("the header's halves overlap the camera", "notch", "Sources/Vitruvian/Core/Notch/NotchSupport.swift",
     "        headerCameraGap > 0 ? (contentWidth - headerCameraGap) / 2 : nil\n",
     "        headerCameraGap > 0 ? contentWidth / 2 : nil\n",
     "the header's halves leave exactly the camera between them, or one row spans the top"),
    ("Codex conversation starts its plugins", "agents",
     "Sources/Vitruvian/Services/AgentUsage/AgentCodexServer.swift",
     "process.arguments = [\"-c\", \"features.plugins=false\", \"app-server\"]",
     "process.arguments = [\"app-server\"]",
     "a conversation starts Codex's server with its plugins off"),
]


def run(bazel_flags, test_arguments, timeout):
    """Runs the unit tests once, never from the cache. Returns Bazel's exit
    status (3 when the build passed and a test failed) and its output, which
    holds the test log."""
    command = ["bazel", "test", "--config=macos-app", "--nocache_test_results", "--test_output=all",
               *bazel_flags, *[f"--test_arg={argument}" for argument in test_arguments], UNIT_TESTS]
    process = subprocess.Popen(command, cwd=WORKSPACE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, start_new_session=True)
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate()
        raise RuntimeError("Mutation run timed out; this is not a detected regression")
    return process.returncode, output


def interrupted(signum, _frame):
    # Unwinds through the `finally` that puts the mutated file back.
    raise SystemExit(128 + signum)


def main(bazel_flags):
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGHUP, interrupted)
    paths = sorted({relative for _, _, relative, _, _, _ in MUTATIONS})
    dirty = subprocess.check_output(["git", "status", "--porcelain", "--", *paths], cwd=ROOT, text=True)
    if dirty:
        raise RuntimeError("Commit or stash these first; the checks edit them in place:\n" + dirty)

    print("Checking the unmodified baseline…", flush=True)
    status, output = run(bazel_flags, [], timeout=3600)
    if status != 0 or "TESTS OK" not in output:
        raise RuntimeError("Baseline failed:\n" + output[-12000:])
    for name, group, relative, before, after, diagnostic in MUTATIONS:
        path = ROOT / relative
        original = path.read_text()
        if original.count(before) != 1:
            raise RuntimeError(f"Mutation fixture needs updating: {name}")
        print(f"Checking: {name}…", flush=True)
        try:
            path.write_text(original.replace(before, after))
            status, output = run(bazel_flags, ["--suite=" + group], timeout=1800)
            if status != 3 or "TESTS FAILED" not in output or diagnostic not in output:
                raise RuntimeError(f"Mutation was not caught by its intended assertion: {name}\n{output[-12000:]}")
            print(f"DETECTED: {name}", flush=True)
        finally:
            path.write_text(original)
    print(f"MUTATION CHECKS OK ({len(MUTATIONS)} regressions detected)", flush=True)


if __name__ == "__main__":
    main(sys.argv[1:])
