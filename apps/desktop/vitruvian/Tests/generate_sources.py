#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Compile selected production methods against test doubles, without an app.

Bodies are read verbatim on every build, never copied into a maintained fixture.
The narrow declaration/indentation contract fails closed if a method moves or
changes shape; the Swift compiler then checks the generated source normally.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build/generated-tests"


# A `package` modifier, after the indentation and any attributes, as code that
# moved into its own module spells it.
_PACKAGE_MODIFIER = re.compile(r"^( *(?:@[\w.]+(?:\([^()\n]*\))? +)*)package ", re.M)


# The island reads its preferences, the pointer, Reduce Motion and the main
# queue's timers through the environment it was built with
# (`NotchService.Environment`). Its copies here still stand in for the
# process-wide ones, so they read the text as it was before those seams.
_NOTCH = "Sources/Vitruvian/Services/Notch/NotchService.swift"
_NOTCH_DEFAULTS = [
    (re.compile(r"\[defaults\] in "), ""),
    (re.compile(r"\.isAvailable\(in: defaults\)"), ".isAvailable"),
    (re.compile(r", in: defaults\)"), ")"),
    (re.compile(r"\(in: defaults\)"), "()"),
    (re.compile(r"(?<![\w.])(?:self\.)?defaults\."), "UserDefaults.standard."),
    (re.compile(r"(?<![\w.])(?:self\.)?pointer\(\)"), "NSEvent.mouseLocation"),
    (re.compile(r"(?<![\w.])reducesMotion\(\)"), "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion"),
    (re.compile(r"(?<![\w.])schedule\((.+), work\)"), r"DispatchQueue.main.asyncAfter(deadline: .now() + \1, execute: work)"),
]
# The services the island calls (`NotchIslandServices`), mapped back to the
# shared instances its copies stand in for.
_NOTCH_SERVICES = [
    ('choosingDownloadFolder', 'NotchDownloadService.shared.isChoosingFolder'),
    ('setMonitorDetailNeeds(', 'SystemMonitor.shared.setNotchDetailNeeds('),
    ('playLockSound(locking:', 'NotchLockScreenService.shared.playSound(locking:'),
    ('rememberPasteTarget()', 'ClipboardHistoryService.shared.rememberPasteTarget()'),
    ('showNormalMenuPanel()', 'MenuPanelFocus.shared.showNormalPanel()'),
    ('suspendAccessories()', 'NotchAccessoryService.shared.suspend()'),
    ('dismissNotification(', 'NotchNotificationService.shared.dismiss('),
    ('keepsCalendarPrompt', 'Permissions.shared.keepsCalendarPrompt'),
    ('openingNotification', 'NotchNotificationService.shared.openingID'),
    ('syncNotifications()', 'NotchNotificationService.shared.syncWithPreferences()'),
    ('stopNotifications()', 'NotchNotificationService.shared.stop()'),
    ('captureScreenshot()', 'ScreenshotService.shared.capture()'),
    ('openNotchSettings()', 'SettingsRouter.shared.request(FeatureSettingsDestination(.notch))'),
    ('mediaContentHeight', 'NotchFileToolsService.shared.mediaContentHeight'),
    ('setMonitorVisible(', 'SystemMonitor.shared.setNotchVisible('),
    ('skipTrack(forward:', 'NotchMusicService.shared.skipFromGesture(forward:'),
    ('toggleMicrophone()', 'MicMuteService.shared.toggle()'),
    ('calendarCountdown', 'NotchCalendarService.shared.countdown'),
    ('keepsCameraPrompt', 'CameraPreviewService.shared.keepsNotchPermissionPrompt'),
    ('pauseAgentUsage()', 'AgentUsageService.shared.pause()'),
    ('syncAccessories()', 'NotchAccessoryService.shared.syncWithPreferences()'),
    ('stopAccessories()', 'NotchAccessoryService.shared.stop()'),
    ('closeLockScreen()', 'NotchLockScreenService.shared.close()'),
    ('openNotification(', 'NotchNotificationService.shared.open('),
    ('toggleKeepAwake()', 'KeepAwakeManager.shared.toggle()'),
    ('toggleRecording()', 'ScreenRecorderService.shared.toggle()'),
    ('keepAwakeEndDate', 'KeepAwakeManager.shared.endDate'),
    ('syncAudioLevel()', 'NotchAudioLevelService.shared.syncWithPreferences()'),
    ('stopAudioLevel()', 'NotchAudioLevelService.shared.stop()'),
    ('syncAgentUsage()', 'AgentUsageService.shared.syncWithPreferences()'),
    ('stopAgentUsage()', 'AgentUsageService.shared.stop()'),
    ('showCommandBar()', 'CommandBarService.shared.show()'),
    ('showScratchpad()', 'ScratchpadService.shared.show()'),
    ('keepAwakeActive', 'KeepAwakeManager.shared.isActive'),
    ('importingLyrics', 'NotchLyricsService.shared.isImporting'),
    ('scratchpadModal', 'ScratchpadService.shared.modalInteractionActive'),
    ('offersMediaDrop', 'NotchFileToolsService.shared.offersMediaDrop'),
    ('syncDownloads()', 'NotchDownloadService.shared.syncWithPreferences()'),
    ('stopDownloads()', 'NotchDownloadService.shared.stop()'),
    ('syncFileTools()', 'NotchFileToolsService.shared.syncWithPreferences()'),
    ('stopFileTools()', 'NotchFileToolsService.shared.stop()'),
    ('syncLockScreen(', 'NotchLockScreenService.shared.sync('),
    ('mediaPresented', 'NotchFileToolsService.shared.mediaPresented'),
    ('systemSnapshot', 'SystemMonitor.shared.snapshot'),
    ('suspendTimer()', 'NotchTimerService.shared.suspend()'),
    ('syncCalendar()', 'NotchCalendarService.shared.syncWithPreferences()'),
    ('stopCalendar()', 'NotchCalendarService.shared.stop()'),
    ('prepareTools()', 'QuickLauncherService.shared.prepareForPresentation()'),
    ('activeUtility', 'QuickLauncherService.shared.activeUtility'),
    ('updateOffered', 'UpdateService.shared.state.isOffer'),
    ('timerSession', 'NotchTimerService.shared.session'),
    ('editingTools', 'QuickLauncherService.shared.isEditing'),
    ('visibleTools', 'QuickLauncherService.shared.visibleItems'),
    ('startMusic()', 'NotchMusicService.shared.start()'),
    ('stopLyrics()', 'NotchLyricsService.shared.stop()'),
    ('hideCamera()', 'CameraPreviewService.shared.hideEmbedded()'),
    ('watchActive', 'NotchWatchService.shared.isActive'),
    ('stopMusic()', 'NotchMusicService.shared.stop()'),
    ('syncTimer()', 'NotchTimerService.shared.syncWithPreferences()'),
    ('stopTimer()', 'NotchTimerService.shared.stop()'),
    ('syncWatch()', 'NotchWatchService.shared.syncWithPreferences()'),
    ('stopWatch()', 'NotchWatchService.shared.stop()'),
    ('agentUsage', 'AgentUsageService.shared.snapshot'),
    ('downloads', 'NotchDownloadService.shared.items'),
    ('playback', 'NotchMusicService.shared.playback'),
    ("showSettingsModule(module)", "SettingsRouter.shared.notchModule = module"),
]
_NOTCH_DEFAULTS += [(re.compile(r"\[services\] in "), "")] + [
    (re.compile(r"(?<![\w.])(?:self\.)?services\." + re.escape(member)), old.replace("\\", "\\\\"))
    for member, old in _NOTCH_SERVICES]


def _source(path):
    """A production file's text as the extractions here expect it: without the
    `package` modifiers that its module needs and these copies do not. Each line
    keeps its number, so `#sourceLocation` still points at the right line."""
    text = _PACKAGE_MODIFIER.sub(r"\1", (ROOT / path).read_text())
    if path == _NOTCH:
        for pattern, replacement in _NOTCH_DEFAULTS:
            text = pattern.sub(replacement, text)
    return text


def declaration(path, prefix, scope=None, keep_nonisolated=False):
    lines = _source(path).splitlines(keepends=True)
    lower, upper = 0, len(lines)
    if scope is not None:
        scopes = [i for i, line in enumerate(lines)
                  if line.startswith(scope)]
        if len(scopes) != 1:
            raise ValueError(f"Expected one scope {scope!r} in {path}")
        lower = scopes[0] + 1
        upper = next(i for i in range(lower, len(lines)) if lines[i].rstrip() == "}")
    starts = [i for i in range(lower, upper) if lines[i].startswith(prefix)]
    if len(starts) != 1:
        raise ValueError(f"Expected one declaration {prefix!r} in {path}")
    start = starts[0]
    indent = prefix[:len(prefix) - len(prefix.lstrip())]
    end = next(i for i in range(start + 1, len(lines)) if lines[i].rstrip() == indent + "}")
    # The tests default to the main actor, and a copy runs there unless it
    # keeps the `nonisolated` written on the line above it. A copy whose
    # closures the tests run on a queue must keep it, or they fail the
    # main-thread check.
    while keep_nonisolated and start > lower and lines[start - 1].strip() == "nonisolated":
        start -= 1
    body = "".join(lines[start:end + 1])
    return f'#sourceLocation(file: {json.dumps(path)}, line: {start + 1})\n{body}\n#sourceLocation()\n'


def write(name, text):
    path = OUTPUT / name
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def availability_declaration(path, prefix):
    return declaration(path, prefix).replace(".feature.isAvailable", ".feature.isAvailable(in: ReviewDefaults.current)")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    panel = "Sources/Vitruvian/App/AppDelegate.swift"
    write("MenuPanelRecovery.swift", "import AppKit\nimport Foundation\n"
          + "extension MenuPanelRecoveryTests {\nfinal class Host: Fixture {\n"
          + "".join(declaration(panel, prefix).replace("private ", "") for prefix in [
              "    private struct PanelAnchor", "    private func statusButtonMidX(",
              "    private func statusScreen(", "    private func positionSettingsWindow(",
              "    private var freshStatusClick:", "    private func captureStatusClick(",
              "    private func correctedPopoverMidX(", "    private func resolvePanelAnchor(",
              "    private func frameStillDescribesMenuBar(", "    private func statusFrameNeedsAnchorOverride(",
              "    private func anchorVisibleFrame(", "    private func applyPopoverDriftFrame(",
              "    private func beginPopoverDriftCorrection(window: NSWindow, anchor: PanelAnchor) {",
              "    private func armPopoverDriftCorrection(", "    private func endPopoverDriftCorrection(",
              "    private func showPopover(", "    func popoverWillClose(", "    func popoverDidClose(",
              "    private func releasePanelResources(", "    private func anchorAfterForeignClose(",
              "    private func reopenPanelAfterForeignClose(", "    private func shouldDismissPopover(",
              "    private func closePopoverNow("])
          + "var popoverAnchor: PanelAnchor?\nvar lastGoodPanelAnchor: PanelAnchor?\n"
          + "}\n}\n")
    notch = "Sources/Vitruvian/Services/Notch/NotchService.swift"
    scratchpad_service = "Sources/Vitruvian/Services/QuickTools/ScratchpadService.swift"
    scratchpad_view = "Sources/Vitruvian/UI/Notch/NotchScratchpadView.swift"
    write("NotchCompact.swift", "import AppKit\nimport SwiftUI\nextension NotchCompactTests {\n"
          + declaration("Sources/Vitruvian/UI/Notch/NotchCameraView.swift", "struct NotchCameraView:")
          + declaration("Sources/Vitruvian/UI/Notch/NotchCalendarView.swift", "private struct NotchCalendarEventRow:")
              .replace("private struct", "struct", 1)
          + declaration("Sources/Vitruvian/UI/Notch/NotchCalendarView.swift", "private struct NotchCountdownChoice:")
              .replace("private struct", "struct", 1)
          + declaration("Sources/Vitruvian/UI/Notch/NotchComponents.swift", "struct NotchRail<")
          + declaration("Sources/Vitruvian/Design/PlainTextEditor.swift", "struct PlainTextEditor:")
          + declaration(scratchpad_view, "struct NotchScratchpadView:")
          + "}\n"
          + declaration("Sources/Vitruvian/UI/Notch/NotchCalendarView.swift", "extension NotchCalendarColor {")
          + "extension NotchCompactTests.ScratchpadService {\n"
          + declaration(scratchpad_service, "    func clear(")
          + "}\nextension NotchCompactTests.Floating {\n"
          + declaration(scratchpad_service, "    private func focusText(").replace("private func", "func", 1)
          + "}\nextension NotchCompactTests.Embedded {\n"
          + declaration(scratchpad_view, "    private func focusEditor(").replace("private func", "func", 1)
          + "}\nextension NotchCompactTests.Page {\n"
          + declaration("Sources/Vitruvian/UI/Notch/NotchView.swift", "    private var pageSize:")
              .replace("private var", "var", 1).replace("NotchSupport.controls()", "controls")
              .replace("NotchTimerService.shared", "NotchCompactTests.NotchTimerService.shared")
          + "}\n")
    canvas = "Sources/Vitruvian/Services/Notch/NotchWindowHost.swift"
    write("NotchHover.swift", "import AppKit\nextension NotchHoverTests {\nfinal class Service: State {\n"
          + declaration(notch, "    func show(_ incoming:").replace("NotchSupport.routes(incoming.event)", "true")
            .replace("    func", "    @discardableResult\n    func", 1)
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    private var hiddenUntilHover:", "    private var hiddenAtRestInFullscreen:", "    func hover(",
              "    private func syncHoverExitMonitoring(", "    private func removeHoverExitMonitors(",
              "    var showsCompactActivityPicker:",
              "    private func missionControlDidRestore()",
              "    private var holdsNotification:", "    private func holdNotification(",
              "    private func syncNoticeWithPreferences(",
              "    private func releaseNotification(", "    private func scheduleNoticeDismissal(",
              "    private func dismissNotice(", "    private func endDeparture(", "    private var noticeCanPresent:",
              "    private func syncHiddenHoverMonitoring(", "    private func removeHiddenHoverMonitors(",
              "    private func scheduleTrackNotice(", "    private func releaseTrackHold(",
              "    private func holdEndingTrack("])
          .replace("NotchSupport.routes(notice.event)", "routesNotices")
          + "}\n}\n")
    music_visibility = "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
        "    private var hiddenUntilHover:", "    var fullscreenCompact:", "    var idleContent:", "    var hasMusicActivity:", "    var compactActivity:",
        "    var compactActivityGeometry:", "    private func compactGeometry(", "    var compactActivities:",
        "    var compactCompanion:",
        "    var surfaceSize:", "    func collapse(",
        "    private func detachCaptureIfClosingOnCollapse(", "    func endCaptureControls(",
        "    private func syncVisibleConsumers(", "    private func releaseMonitor("])
    for call in ["NotchSupport.controls", "NotchSupport.watchesMusicActivity", "NotchSupport.idleContent"]:
        music_visibility = music_visibility.replace(call + "()", call + "(in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("NotchSupport.routes(.track)",
                                                "NotchSupport.routes(.track, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("UserDefaults.standard", "ReviewDefaults.current!")
    music_visibility = music_visibility.replace("calendar: hasCalendarActivity", "calendar: false")
    music_visibility = music_visibility.replace("playback?.isPlaying == true)",
                                                "playback?.isPlaying == true, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("captureControls: captureControls != nil)",
                                                "captureControls: captureControls != nil, in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace(
        "NotchDownloadService.shared.items.first { $0.active && !$0.completed }?.name", "downloadName")
    music_visibility = music_visibility.replace("AppFeature.monitorDisk.isAvailable",
                                                "AppFeature.monitorDisk.isAvailable(in: ReviewDefaults.current)")
    music_visibility = music_visibility.replace("AppFeature.fanControl.isAvailable",
                                                "AppFeature.fanControl.isAvailable(in: ReviewDefaults.current)")
    write("NotchMusicVisibility.swift", "import Foundation\nextension NotchMusicVisibilityTests {\n"
          + "final class Service: State {\n" + music_visibility + "}\n}\n")
    write("NotchPresentationRefresh.swift", "import AppKit\nimport Foundation\nimport Combine\nimport SwiftUI\n"
          + "extension NotchPresentationRefreshContract {\nfinal class Service: State {\n"
          + "func hover(_ entered: Bool) {\nlet wasInside = inside\n"
          + "inside = windowHost?.containsHover(NSEvent.mouseLocation) == true\n"
          + "hoverState.update(pointerInside: inside)\nupdateCaptureControlsHover(wasInside: wasInside)\n}\n"
          + "".join(declaration(notch, prefix).replace("    private ", "    ", 1) for prefix in [
              "    func collapseCaptureControls()", "    func expandCaptureControls()",
              "    private func setCaptureSelectionInProgress(", "    func scheduleCaptureControlsCollapse(",
              "    private func updateCaptureControlsHover(", "    private func updateCaptureControlsClickThrough()",
              "    private func removeCaptureControlsClickThrough()", "    private func missionControlDidRestore()",
              "    func endCaptureControls()"])
          + declaration(notch, "    func presentCaptureControls(")
              .replace("ScreenCaptureSelectionOptions", "CaptureOptions")
              .replace(".receive(on: DispatchQueue.main)", "")
              .replace("panel?.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)", "panel?.level = 2")
          + declaration(notch, "    private var hiddenUntilHover:").replace("private var", "var", 1)
          + declaration(notch, "    private var hiddenAtRestInFullscreen:").replace("private var", "var", 1)
          + declaration(notch, "    var acceptsUserInteraction:")
          + declaration(notch, "    var acceptsSystemFeedback:")
          + declaration(notch, "    var showsSystemFeedback:")
          + declaration(notch, "    var usesGlassSurface:")
          + declaration(notch, "    var expandedGeometry:").replace("var expandedGeometry", "override var expandedGeometry", 1)
          + declaration(notch, "    private func compactMusicTransition(").replace("private func", "func", 1)
          + declaration(notch, "    private func rememberPresentedMusic(").replace("private func", "func", 1)
          + declaration(notch, "    private func switchCompactSelection(").replace("private func", "func", 1)
          + declaration(notch, "    func refreshPresentation(")
              .replace("NotchSupport.coversMenus()", "UserDefaults.standard.coversMenus")
          + declaration(notch, "    private func applyMenuSpace(").replace("private func", "func", 1)
          + declaration(notch, "    func presentCapture(")
              .replace("content: AnyView, actions: AnyView? = nil", "content: Bool, actions: Bool? = nil")
              .replace("NotchSupport.routes(.capture)", "routesCaptures")
          + declaration(notch, "    func updateCaptureHeight(")
          + declaration(notch, "    func removeCapture(")
          + declaration(notch, "    private func clearCapture(")
          + declaration(notch, "    private func detachCaptureIfClosingOnCollapse(")
          + "}\n}\nextension NotchPresentationRefreshContract.Host {\n"
          + declaration(canvas, "    func setMouseEventsIgnored(")
          + declaration(canvas, "    private func restoreFromMissionControl(").replace("private func", "func", 1)
          + "}\n")
    renderer = "Sources/Vitruvian/Services/MenuBar/MenuBarRenderer.swift"
    metric_cases = "\n".join(line for line in declaration("Sources/Vitruvian/Services/SystemMonitor/MetricDetailKind.swift", "enum MetricDetailKind:").splitlines()
                             if line.startswith("    case "))
    menu_metric_cases = "\n".join(line for line in declaration(renderer, "enum MenuBarMetric:").splitlines()
                                  if line.startswith("    case "))
    write("NotchDestinations.swift", "import Foundation\n\nextension NotchDestinationContract {\n"
          + "enum MetricDetailKind: String {\n" + metric_cases + "\n}\n"
          + "enum MenuBarMetric: String, CaseIterable {\n" + menu_metric_cases + "\n"
          + declaration(renderer, "    var feature: AppFeature")
          + declaration("Sources/Vitruvian/Services/SystemMonitor/MetricDetailKind.swift", "    var detailKind:") + "}\n"
          + "final class Service: State {\n"
          + "struct Collaborators { var feedbackRoutingDidChange: () -> Void = {\n"
          + "if AppFeature.mixer.isAvailable(in: ReviewDefaults.current) { PreciseVolumeRollerService.shared.syncWithPreferences() }\n"
          + "if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }\n"
          + "} }\nstatic var collaborators = Collaborators()\n"
          + "func syncWithPreferences() { presentationSyncs += 1; refreshModules(); syncVisibleConsumers(); NotchTimerService.shared.syncWithPreferences() }\n"
          + availability_declaration(notch, "    private func metricIsAvailable(")
          + declaration(notch, "    private func refreshModules(")
              .replace("NotchSupport.modules()", "NotchSupport.modules(in: ReviewDefaults.current)")
          + declaration(notch, "    func open(_ module:")
              .replace("NotchSupport.isEnabled()", "NotchSupport.isEnabled(in: ReviewDefaults.current)")
          + "func removeHoverExitMonitors() {}\n"
          + declaration(notch, "    func showScratchpad(")
              .replace("NotchSupport.routesScratchpad()", "NotchSupport.routesScratchpad(in: ReviewDefaults.current)")
          + declaration(notch, "    func toggleSections()")
          + declaration(notch, "    func goBack()")
          + declaration(notch, "    private func stepBack()").replace("private func", "func", 1)
          + declaration(notch, "    func setPageLayer(")
          + declaration(notch, "    func openAppPanel(")
          + declaration(notch, "    func showMetric(")
          + declaration(notch, "    var reopeningDestination:")
              .replace("UserDefaults.standard", "ReviewDefaults.current!")
          + declaration(notch, "    func openActivity(")
              .replace("UserDefaults.standard", "ReviewDefaults.current!")
          + declaration(notch, "    var reopeningModule:")
          + declaration(notch, "    private func updateSession(").replace("private func", "func", 1)
              .replace("NotchLockScreenSupport.playsSounds()", "NotchLockScreenSupport.playsSounds(in: ReviewDefaults.current)")
          + "}\n}\n")
    factories = []
    pattern = r"static\s+func\s+(\w+)\s*\(\s*_\s+\w+:\s*AppLanguage\s*\)\s*->"
    for path in sorted((ROOT / "Sources/Vitruvian/Core").glob("*Strings.swift")):
        source = path.read_text()
        if "extension FeatureStrings" in source or "enum FeatureStrings" in source:
            scopes = re.findall(r"(?:extension|enum) FeatureStrings \{(.*?)^\}", source, re.S | re.M)
            names = [name for scope in scopes for name in re.findall(pattern, scope)]
            if not names:
                raise ValueError(f"No language factory found in {path}")
            factories.extend(names)
    if not factories or len(factories) != len(set(factories)):
        raise ValueError("Missing or duplicate localization factories")
    write("LocalizationCatalog.swift", "extension LocalizationTests {\n"
          + "static let factories: [(String, (AppLanguage) -> Any)] = [\n"
          + "".join(f'("{name}", {{ FeatureStrings.{name}($0) }}),\n' for name in factories)
          + "]\n}\n")


if __name__ == "__main__":
    main()
