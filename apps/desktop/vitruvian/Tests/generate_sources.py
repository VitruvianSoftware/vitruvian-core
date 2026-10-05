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


def _source(path):
    """A production file's text as the extractions here expect it: without the
    `package` modifiers that its module needs and these copies do not. Each line
    keeps its number, so `#sourceLocation` still points at the right line."""
    return _PACKAGE_MODIFIER.sub(r"\1", (ROOT / path).read_text())


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
    write("UpdateIntroFlow.swift", "import AppKit\nimport Foundation\n"
          + "extension UpdateIntroFlowTests {\nfinal class Host: Fixture {\n"
          + "".join(declaration(panel, prefix).replace("    private ", "    ", 1) for prefix in [
              "    private func presentUpdateIntros()", "    private func showUpdateHighlightsIfNeeded()",
              "    private func markUpdateHighlightsSeen()", "    private func showSupportUpdateIntroIfNeeded()",
              "    func windowShouldClose(", "    func windowWillClose(", "    private func markOnboardingComplete()",
              "    private func markSupportUpdateIntroSeenIfCurrentUpdate()", "    private func markSupportUpdateIntroSeen()"])
          + "}\n}\n")
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
    brightness = "Sources/Vitruvian/Services/Display/BrightnessService.swift"
    write("DisplayRestoration.swift", "import CoreGraphics\nimport Foundation\n"
          + "extension DisplayRestorationTests {\nfinal class BrightnessService: Fixture {\n"
          + "typealias DisplayControlFailure = VitruvianServices.BrightnessService.DisplayControlFailure\n"
          + "".join(declaration(brightness, prefix).replace("private ", "", 1) for prefix in [
              "    private static func configureDisplay(", "    private func restoreDisplay(",
              "    private func syncLidObserver(", "    private func restoreDeferredDisplays(",
              "    private func restoreManagedDisplays(", "    func restoreDisplaysLeftOff(",
              "    private func commitDisplayToggle(", "    private func finishDisplayToggle(",
              "    private func restoreManagedDisplayIfHeadless("])
          + "}\n}\n")
    write("BrightnessStep.swift", "import CoreGraphics\nimport Foundation\nimport os\n"
          + "extension BrightnessStepTests {\n"
          + "".join(declaration(brightness, prefix).replace("private ", "", 1) for prefix in [
              "    private struct Route", "    private enum DDCProbe"])
          + "final class Service: Fixture {\n"
          + declaration(brightness, "    private func step(").replace("private ", "", 1)
          + declaration(brightness, "    private func writeExtendedBrightness(").replace("private ", "", 1)
          + declaration(brightness, "    private static func writeSystemBrightness(").replace("private ", "", 1)
          + "}\n}\n")
    uninstall = "Sources/Vitruvian/Services/Uninstall/AppUninstaller.swift"
    bar = "Sources/Vitruvian/Services/CommandBar/CommandBarService.swift"
    write("CommandBarEmojiBodies.swift", "import Foundation\n"
          + "extension CommandBarEmojiContract.Catalog {\n"
          + declaration("Sources/Vitruvian/Services/CommandBar/CommandBarCatalog.swift",
                        "    static func emojiEntries(")
          + "}\nextension CommandBarEmojiContract.Service {\n"
          + "".join(declaration(bar, prefix).replace("private func", "func", 1)
                    for prefix in ["    struct RowAction:", "    private func skinToneActions(",
                                   "    private func recordUsage(", "    private func finish("])
          + "}\n")
    write("UninstallerFlow.swift", "import AppKit\nimport Carbon.HIToolbox\nimport Combine\n"
          + "extension UninstallerFlowTests {\n"
          + declaration(uninstall, "    enum Phase:")
          + "typealias Mode = VitruvianServices.CommandBarService.Mode\n"
          + "final class Uninstaller: UninstallerState {\nstatic let shared = Uninstaller()\n"
          + "".join(declaration(uninstall, prefix) for prefix in [
              "    var isRemoving: Bool", "    func select(appURL:",
              "    func reset()", "    func setInclude(", "    struct HomebrewRemovalConfirmation",
              "    var homebrewRemovalConfirmation:", "    func removeSelectedWithHomebrew("])
          + "}\nfinal class Service: ServiceState {\n"
          + "".join(declaration(bar, prefix).replace("private func", "func", 1) for prefix in [
              "    @Published var query", "    private func beginUninstallReview(",
              "    private func handleUninstallKey(", "    func stepBack()",
              "    private func finishUninstallReview()"])
          + "}\n}\nextension UninstallerFlowTests.Finder {\n"
          + declaration("Sources/Vitruvian/Services/Finder/FinderCutPaste.swift", "    static func selectionURLs(")
          + "}\n")
    dock = "Sources/Vitruvian/Services/DockPreview/DockPreviewService.swift"
    # The raw wheel tap runs as shipped: linear scrolling's cap, carry and
    # write-back, then the direction change. Only the services it asks and
    # the defaults it reads are fixtures.
    # Entire input/mute services retain their production control flow. Only
    # visibility, scheduling, defaults and HAL transport are replaced by fixtures.
    input_source = "Sources/Vitruvian/Services/Audio/AudioInputDeviceManager.swift"
    mute_source = "Sources/Vitruvian/Services/QuickTools/MicMuteService.swift"
    input_bodies = (declaration(input_source, "struct MixerInputDevice:")
                    + declaration(input_source, "final class AudioInputDeviceManager:")
                    + declaration(mute_source, "final class MicMuteService:"))
    input_bodies = (input_bodies.replace("fileprivate ", "")
                   .replace("private(set) ", "").replace("private ", "")
                   .replace("static let shared =", "static var shared ="))
    for operation in ("HasProperty", "IsPropertySettable", "GetPropertyDataSize",
                      "GetPropertyData", "SetPropertyData", "AddPropertyListener",
                      "RemovePropertyListener"):
        input_bodies = input_bodies.replace("AudioObject" + operation + "(", "HAL." + operation + "(")
    write("MixerInputVolume.swift", "import Foundation\nimport Combine\nimport CoreAudio\nimport AudioToolbox\n"
          + "extension MixerInputVolumeContract {\n" + input_bodies + "}\n")
    mixer = "Sources/Vitruvian/Services/Audio/AppVolumeMixer.swift"
    write("MixerOutputAdjustment.swift", "import CoreAudio\nimport Foundation\n"
          + "extension MixerOutputAdjustmentContract {\nfinal class Mixer {\n"
          + declaration(mixer, "    private struct OutputAdjustment {")
          + declaration(mixer, "    private struct OutputStep {")
          + "private var queuedOutputSteps: [OutputStep] = []\nvar outputStepReadInFlight = false\nvar outputStepReadGeneration = 0\n"
          + "static func hasSettableOutputVolume(for device: AudioObjectID) -> Bool { true }\n"
          + "static func outputVolume(for device: AudioObjectID) -> Float32? { Hardware.volume }\n"
          + "static func outputMuted(for device: AudioObjectID) -> Bool? { Hardware.muted }\n"
          + "var systemOutputVolume: Double?\nvar systemOutputMuted: Bool?\n"
          + "var outputControlListenerDevice: AudioObjectID?\n"
          + "var outputControlListenerAddresses: [AudioObjectPropertyAddress] = []\n"
          + "var outputControlRefreshGeneration = 0\n"
          + "private var pendingOutputAdjustment: OutputAdjustment?\nprivate var outputWriteInFlight: OutputAdjustment?\n"
          + "let outputControlLock = NSLock()\nvar outputControlLifetime = UUID()\nlet halQueue = Queue()\n"
          + "var controlRefreshes: [AudioObjectID] = []\nvar listenerRefreshes = 0\n"
          + "static let outputControlListenerCallback: AudioObjectPropertyListenerProc = { _, _, _, _ in noErr }\n"
          + "var listenerClient: UnsafeMutableRawPointer? { nil }\n"
          + "static func defaultOutputDeviceID() -> AudioObjectID { Hardware.device }\n"
          + "static func setOutputVolume(_ value: Float, for device: AudioObjectID) -> Bool {\n"
          + "Hardware.writes.append(.init(device: device, volume: value, muted: nil))\n"
          + "let after = Hardware.afterVolumeWrite; Hardware.afterVolumeWrite = nil; after?()\nreturn Hardware.succeeds\n}\n"
          + "static func setOutputMuted(_ value: Bool, for device: AudioObjectID) -> Bool {\n"
          + "Hardware.writes.append(.init(device: device, volume: nil, muted: value)); return Hardware.succeeds\n}\n"
          + "func scheduleListenerRefresh() { listenerRefreshes += 1 }\n"
          + "func scheduleOutputControlRefresh(for device: AudioObjectID) { controlRefreshes.append(device) }\n"
          + "func selectOutput(_ device: AudioObjectID?, volume: Double?, muted: Bool?) {\n"
          + "removeOutputControlListeners(); outputControlListenerDevice = device; applyOutputControls(volume: volume, muted: muted)\n}\n"
          + "func readSnapshot(volume: Double?, muted: Bool?) { applyOutputControls(volume: volume, muted: muted) }\n"
          + "".join(declaration(mixer, prefix) for prefix in [
              "    func requestOutputAdjustment(", "    private func removeOutputControlListeners(",
              "    func requestOutputStep(", "    func requestOutputMuteToggle(",
              "    private func enqueueOutputKey(", "    private func settleQueuedOutputSteps(",
              "    private func applyQueuedOutputSteps(",
              "    private func isCurrentOutputAdjustment(", "    private var hasCurrentOutputAdjustment:",
              "    private func applyOutputControls(", "    private func drainOutputAdjustment("])
          + "}\n}\n")

    playback_adapter = "Sources/NowPlayingAdapter/NowPlayingSelection.swift"
    adapter_entry = "Sources/NowPlayingAdapter/NowPlayingAdapter.swift"
    # Only the clock changes, so tests drive the wait for a chosen source's track.
    write("NotchPlaybackRouting.swift", "import Foundation\nimport ObjectiveC\nextension NotchPlaybackRoutingContract {\n"
          + declaration(playback_adapter, "    private struct Identity:").replace("private struct", "struct", 1)
          + declaration(playback_adapter, "    private static func playPauseCommand(")
          + declaration(playback_adapter, "    static var target:")
          + declaration(playback_adapter, "    static var sourceReply:")
          + declaration(playback_adapter, "    static func choose(")
          + declaration(playback_adapter, "    static func select()")
            .replace("ProcessInfo.processInfo.systemUptime", "uptime")
          + declaration(playback_adapter, "    static func publish(").replace("    static func", "    @discardableResult\n    static func", 1)
          + declaration(playback_adapter, "    static func updatePlayPauseCommand(")
          + declaration(playback_adapter, "    static func validatedTarget(")
          + declaration(playback_adapter, "    static func readInfo(")
          + declaration(playback_adapter, "    static func supportedCommands(")
          + declaration(playback_adapter, "    private static func currentPlayerPID(").replace("private static", "static", 1)
          + declaration(playback_adapter, "    static func send(")
          + declaration(playback_adapter, "    private static func makeTarget(").replace("private static", "static", 1)
          + declaration(adapter_entry, "private func sendPlaybackCommand(").replace("private func", "static func", 1)
          + declaration(adapter_entry, "func encodedReply(").replace("func encodedReply", "static func encodedReply", 1)
          + "}\n")
    shelf = "Sources/Vitruvian/Services/Shelf/ShelfService.swift"
    notch = "Sources/Vitruvian/Services/Notch/NotchService.swift"
    # The composition root wires the island's collaborators; each contract
    # wires its own stand-ins the way main.swift wires the services.
    write("NotchFullscreen.swift", "import CoreGraphics\nimport Foundation\nextension NotchFullscreenTests {\n"
          + "typealias Topology = VitruvianServices.SpaceWindowBridge.Topology\n"
          + "final class Service: State {\n"
          + "struct Collaborators { var feedbackRoutingDidChange: () -> Void = {\n"
          + "if AppFeature.mixer.isAvailable { PreciseVolumeRollerService.shared.syncWithPreferences() }\n"
          + "if AppFeature.brightness.isAvailable { BrightnessService.shared.syncWithPreferences() }\n"
          + "} }\nstatic var collaborators = Collaborators()\n"
          + declaration(notch, "    var acceptsUserInteraction: Bool {")
          + declaration(notch, "    var acceptsSystemFeedback: Bool {")
          + declaration(notch, "    private func updateFullscreenVisibility(").replace("private func", "func", 1)
          + declaration(notch, "    private func fullscreenEnvironmentDidChange()").replace("private func", "func", 1)
          + "}\nfinal class PreciseVolumeRollerService: VolumeState {\n"
          + "static let shared = PreciseVolumeRollerService()\n"
          + declaration("Sources/Vitruvian/Services/Audio/PreciseVolumeRollerService.swift", "    func syncWithPreferences()")
          + "}\n}\n")
    recorder = "Sources/Vitruvian/Services/Recorder/RecorderEditorController.swift"
    write("RecorderZoomAiming.swift", "import Foundation\nimport Combine\n"
          + "extension RecorderZoomAimingTests {\nfinal class Model: State {\n"
          + declaration(recorder, "    @Published var document:").replace("@Published var", "override var", 1)
          + declaration(recorder, "    @Published var selectedZoomID:")
          + "".join(declaration(recorder, prefix) for prefix in [
              "    private func documentDidChange(", "    func undo()", "    func redo()",
              "    private func apply(_ next:", "    func zoom(_ id:",
              "    func beginAiming(", "    func endAiming(", "    func aim(",
              "    func setSelectedZoomFocus(", "    private func applyDuringInteraction(",
              "    func beginPickingBlurArea(", "    func endPickingBlurArea("])
          + "}\n}\n")
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
    write("NotchScreenRefresh.swift", "import Foundation\n\nextension NotchScreenRefreshContract {\nfinal class Service: State {\n"
          + declaration(notch, "    private func schedulePreferenceSync()").replace("private func", "func", 1)
          + declaration(notch, "    private func screenParametersDidChange()").replace("private func", "func", 1)
          + declaration(notch, "    private func invalidateMenuSpace(").replace("private func", "func", 1)
          + declaration(notch, "    private func applicationDidActivate()").replace("private func", "func", 1)
          + declaration(notch, "    private func syncMenuSpaceMonitoring()").replace("private func", "func", 1)
              .replace("AXIsProcessTrusted()", "accessibilityGranted")
              .replace("NotchSupport.coversMenus()", "coversMenus")
          + declaration(notch, "    private var canFollowPointer:").replace("private var", "var", 1)
          + declaration(notch, "    private func move(to screen:").replace("private func", "func", 1)
          + "}\n}\n")
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
    write("ShelfDropRouting.swift", "import AppKit\n\nextension ShelfDropRoutingContract {\n"
          + declaration(canvas, "struct NotchFileDropActions {")
          + "final class ShelfService: ShelfState {\nstatic var shared = ShelfService()\n"
          + declaration(shelf, "    func acceptDrop(pasteboard:")
          + declaration(shelf, "    func accept(draggingInfo:")
          + declaration(shelf, "    func fileURLs(from")
          + declaration(shelf, "    private func unique(")
          + "}\nfinal class NotchFileToolsService: FileToolsState {\nstatic var shared = NotchFileToolsService()\n"
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    var offersMediaDrop:")
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    var canAcceptMediaDrop:")
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    func mediaDropContent(")
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    func openMediaDrop(")
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    func updateMediaHeight(",
                        scope="final class NotchFileToolsService:")
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    func hideMedia(")
          + declaration("Sources/Vitruvian/Services/Notch/NotchFileToolsService.swift", "    func showMedia(")
          + "}\nfinal class Notch: NotchState {\n"
          + "struct Collaborators { var shelfAccept: (NSPasteboard) -> Bool = { ShelfService.shared.acceptDrop(pasteboard: $0) } }\n"
          + "static var collaborators = Collaborators()\n"
          + "lazy var fileDrop = ShelfDropRoutingContract.fileDrop(for: self)\n"
          + declaration(notch, "    var choosingFileDropDestination:")
          + declaration(notch, "    var targetsMediaDrop:")
          + declaration(notch, "    var canAcceptFileDrop:")
          + declaration(notch, "    private var mediaDropArea:").replace("private var", "var", 1)
          + declaration(notch, "    func beginFileDrop(")
          + declaration(notch, "    func updateFileDrop(")
          + declaration(notch, "    func endFileDrop(")
          + declaration(notch, "    func accept(_ pasteboard:")
          + declaration(notch, "    private func fileDropLanded(").replace("private func", "func", 1)
          + "}\nfinal class Canvas {\nvar acceptingDrag = false\n"
          + "var dropActions: NotchFileDropActions?\n"
          + "var visibleRect = CGRect(x: 0, y: 0, width: 440, height: 400)\n"
          + "func convert(_ point: CGPoint, from: Int?) -> CGPoint { point }\n"
          + "func containsVisiblePoint(_ point: CGPoint) -> Bool { visibleRect.contains(point) }\n"
          + declaration(canvas, "    func beginDrop(")
          + declaration(canvas, "    func finishDrop(")
          + declaration(canvas, "    override func draggingUpdated(").replace("override func", "func", 1)
          + declaration(canvas, "    override func draggingExited(").replace("override func", "func", 1)
          + declaration(canvas, "    override func performDragOperation(").replace("override func", "func", 1)
          + "}\n}\n")
    switcher = "Sources/Vitruvian/UI/Switcher/SwitcherView.swift"
    switcher_service = "Sources/Vitruvian/Services/Switcher/AppSwitcher.swift"
    write("SwitcherScroll.swift", "import AppKit\nimport SwiftUI\n"
          + "extension SwitcherScrollContract {\nstruct Strip: View {\n"
          + "@ObservedObject var switcher: Model\n"
          + "var instantSelection = false\n"
          + "var iconRowContentWidth: CGFloat { switcher.iconRowLayout.contentWidth(simpleMode: true, windowRow: false) }\n"
          + "var body: some View {\nif selectedWindow != nil {\nlet appWindows = selectedAppWindows\n"
          + "if switcher.simple {\nGroup {\n"
          + declaration(switcher, "                ScrollViewReader { proxy in")
          + "}\n.frame(width: iconRowContentWidth - 2 * SwitcherIconRowLayout.simpleTitlePanelPadding, "
          + "height: 25 * SwitcherIconRowLayout.scale)\n} else {\n"
          + declaration(switcher, "                    ScrollViewReader { proxy in")
          + "}\n}\n}\n"
          + declaration(switcher, "    private var selectedWindow:")
          + declaration(switcher, "    private var selectedAppWindows:")
          + declaration(switcher, "    private func revealSelection(")
          + "}\n}\nextension SwitcherScrollContract.Model {\n"
          + "func search(_ query: String) { searchQuery = query; applySearchFilter(preferredItemID: selectedItemID) }\n"
          + declaration(switcher_service, "    private var selectedItemID:")
          + declaration(switcher_service, "    private func applySearchFilter(")
          + "}\n")
    preview = "Sources/Vitruvian/Services/QuickTools/ScreenshotQuickPreviewController.swift"
    selection = "Sources/Vitruvian/Services/QuickTools/ScreenshotSelectionController.swift"
    refresh_methods = [
        "    private func screenCaptureToolDidChange()",
        "    private func adoptCapturePolicy(",
        "    private func applySource(",
        "    private func loadLiveLoupeImages()",
        "    private func markCapturePending()",
        "    private func captureFullDisplayUnderMouse()",
        "    fileprivate func captureFullScreenFromControl(",
        "    private func captureFullDisplay(",
        "    private func repeatLastRegion()",
        "    fileprivate func confirmWindow(",
        "    fileprivate func confirmRegion(",
        "    fileprivate func confirmColor(",
    ]
    write("ScreenshotSelectionRefresh.swift", "import Foundation\nimport AppKit\nimport SwiftUI\n"
          + "extension ScreenshotSelectionRefreshContract.Chooser {\n"
          + declaration(selection, "    fileprivate func setSelectionInProgress(").replace("fileprivate func", "func", 1)
          + declaration(selection, "    fileprivate var acceptsCaptureInput:").replace("fileprivate var", "var", 1)
          + declaration(selection, "    fileprivate var offersFullScreenCapture:").replace("fileprivate var", "var", 1)
          + declaration(selection, "    fileprivate var acceptsWindowClick:").replace("fileprivate var", "var", 1)
          + declaration(selection, "    func placeFullScreenControlBelowNotch(")
          + declaration(selection, "    private var repeatTargetPanel:").replace("private var", "var", 1)
          + declaration(selection, "    fileprivate var offersRepeatLastRegion:").replace("fileprivate var", "var", 1)
          + "".join(declaration(selection, prefix).replace("fileprivate func", "func", 1)
                    .replace("private func", "func", 1).replace("UserDefaults.standard", "ReviewDefaults.current")
                    for prefix in refresh_methods)
          + "}\nextension ScreenshotSelectionRefreshContract.View {\n"
          + declaration(selection, "    func captureToolDidChange()")
          + declaration(selection, "    func setNotchCaptureControlsHeight(")
          + declaration(selection, "    func refreshFullScreenControlVisibility()")
          + declaration(selection, "    private func pointerIsOverFullScreenControl(").replace("private func", "func", 1)
          + declaration(selection, "    private func updatePointerHover(").replace("private func", "func", 1)
          + declaration(selection, "    private func fullScreenControlHoverChanged(").replace("private func", "func", 1)
          + declaration(selection, "    private func resetFullScreenControlHover(").replace("private func", "func", 1)
          + declaration(selection, "    private func applyDeferredNotchCaptureControlsHeight(").replace("private func", "func", 1)
          + "}\nextension ScreenshotSelectionRefreshContract.SurfaceService {\n"
          + declaration("Sources/Vitruvian/Services/QuickTools/ScreenCaptureService.swift",
                        "    private func connectCaptureControlsSurface(").replace("private func", "func", 1)
          + "}\n"
          + declaration(selection, "private final class PassThroughHostingView<")
              .replace("private final class", "final class", 1))
    write("NotchCaptureKeyboard.swift", "import Foundation\nimport Carbon.HIToolbox\n\nextension NotchCaptureKeyboardContract {\n"
          + "final class NotchService {\nstatic var shared = NotchService()\n"
          + "var presentationWindow: NSPanel? = NSPanel()\nvar acceptsSystemFeedback = true\n"
          + "var expanded = true\nvar selected = NotchModule.captures\nvar showingAppPanel = false\n"
          + "var showingSections = false\nvar selectedMetric: Int?\nvar captureControls: Int?\n"
          + "var captureID: UUID?\nvar captureContent: Bool? = true\n"
          + declaration("Sources/Vitruvian/Services/Notch/NotchService.swift", "    func isCaptureVisible(")
          + "}\nfinal class Preview {\n"
          + "typealias Action = VitruvianServices.ScreenshotQuickPreviewController.Action\n"
          + "var keyMonitor: Any?\nvar closed = false\nvar shownInNotch = true\nlet presentationID = UUID()\n"
          + "var actions: [Action] = []\nfunc perform(_ action: Action) { actions.append(action) }\n"
          + "func close() { closed = true }\nfunc attach(_ panel: NSPanel) { installKeyMonitor(for: panel) }\n"
          + declaration(preview, "    private func installKeyMonitor(for panel:")
          + "}\nfinal class Selection {\n"
          + "final class Options { var controlsInNotch = true; var hasFocusedControl = false }\n"
          + "enum Outcome { case cancelled }\nvar screenCaptureOptions: Options? = Options()\n"
          + "var keyMonitor: Any?\nvar globalKeyMonitor: Any?\nvar spaceIsDown = false\n"
          + "var acceptsWindowClick = true\nvar loupeAcceptsKeyboardActions = false\n"
          + "var actions: [String] = []\nvar draggingPanel: ScreenshotOverlayPanel?\n"
          + 'func finish(_ outcome: Outcome) { actions.append("cancel") }\n'
          + 'func captureFullDisplayUnderMouse() { actions.append("fullDisplay") }\n'
          + "func panelUnderMouse() -> ScreenshotOverlayPanel? { draggingPanel }\n"
          + 'func repeatLastRegion() { actions.append("repeat") }\n'
          + "func selectCaptureTool(for event: NSEvent) -> Bool { false }\n"
          + "static func isScrollingCaptureKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isLoupeKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isCopyColorKey(_ event: NSEvent) -> Bool { false }\n"
          + "static func isNudgeKey(_ event: NSEvent) -> Bool { false }\n"
          + "func toggleScrollingCapture() {}\nfunc toggleLoupe() {}\nfunc copyLoupeColor() {}\n"
          + "func nudgePointer(keyCode: Int, fast: Bool) {}\nfunc attach() { installKeyMonitor() }\n"
          + declaration(selection, "    private static func isRepeatRegionKey(")
          + declaration(selection, "    private static func matchesShortcutKey(")
          + declaration(selection, "    private func installKeyMonitor()")
          + "}\n}\n")
    hop = "Sources/Vitruvian/Services/Switcher/SpaceHop.swift"
    write("PointerOnDisplay.swift", "import AppKit\n"
          + "extension PointerOnDisplayContract.Bridge {\n"
          + "typealias Topology = VitruvianServices.SpaceWindowBridge.Topology\n"
          + "}\nextension PointerOnDisplayContract.Hop {\n"
          + "".join(declaration(hop, prefix).replace("private ", "", 1)
                    for prefix in ["    private enum TravelOutcome {", "    private func stepWithSpaceShortcut()"])
          + "}\nextension PointerOnDisplayContract.Overlay {\n"
          + declaration(selection, "    func refreshGuideVisibility()")
          + "}\nextension PointerOnDisplayContract.Dock {\n"
          + declaration(dock, "    private func isNearDock(").replace("private func", "func", 1)
          + "}\n")

    brightness = "Sources/Vitruvian/Services/Display/BrightnessService.swift"
    write("SoftwareDimmingRoute.swift", "import CoreGraphics\nimport Foundation\n\n"
          + "extension SoftwareDimmingRouteContract {\n"
          + "final class Service {\nlet stateLock = NSLock()\nlet workQueue = Queue()\n"
          + "static let log = Log()\n"
          + "var routes: [CGDirectDisplayID: Route] = [:]\n"
          + "var lastApplied: [CGDirectDisplayID: Double] = [:]\n"
          + "var levelKnownAt: [CGDirectDisplayID: Foundation.Date] = [:]\n"
          + "var pendingLevels: [CGDirectDisplayID: Double] = [:]\n"
          + "var softwareDims: [(id: CGDirectDisplayID, value: Double)] = []\n"
          + "struct GammaTable { var red: [CGGammaValue] = [1]; var green: [CGGammaValue] = [1]; "
          + "var blue: [CGGammaValue] = [1]; var count: UInt32 = 1; var fingerprint: String }\n"
          + "var gammaBaselines: [CGDirectDisplayID: GammaTable] = [:]\n"
          + "var dimmedDisplays = Set<CGDirectDisplayID>()\n"
          + "var softwareSucceeds = true\nvar ddcSucceeds = true\nvar events: [String] = []\n"
          + "var forgottenWriteOnlyPaths: [String] = []\nvar refreshes = 0\n"
          + "static func displayFingerprint(_ id: CGDirectDisplayID) -> String { \"display-\\(id)\" }\n"
          + "func CGSetDisplayTransferByTable(_ id: CGDirectDisplayID, _ count: UInt32, "
          + "_ red: [CGGammaValue], _ green: [CGGammaValue], _ blue: [CGGammaValue]) { "
          + "events.append(\"restore:\\(id)\") }\n"
          + "func forgetWriteOnlyDDCPath(_ path: String?) { forgottenWriteOnlyPaths.append(path ?? \"\") }\n"
          + "@discardableResult func applySoftwareDim(_ id: CGDirectDisplayID, value: Double) -> Bool {\n"
          + "softwareDims.append((id, value)); events.append(\"picture:\\(value)\")\n"
          + "if softwareSucceeds { if value >= 0.999 { dimmedDisplays.remove(id) } else { dimmedDisplays.insert(id) } }\n"
          + "return softwareSucceeds\n}\n"
          + "func ddcSend(to id: CGDirectDisplayID, service: CFTypeRef, packet: [UInt8]) -> Bool {\n"
          + "let value = UInt16(packet[3]) << 8 | UInt16(packet[4])\n"
          + "events.append(\"ddc:\\(value)\"); return ddcSucceeds\n}\n"
          + "func refresh(force: Bool = false) { refreshes += 1 }\n"
          + declaration(brightness, "    func setSoftwareDimmingPreferred(")
          + declaration(brightness, "    func setExtendedDimmingPreferred(")
          + declaration(brightness, "    private func restoreAllGamma(").replace("private func", "func", 1)
          + declaration(brightness, "    private func writeExtendedBrightness(").replace("private func", "func", 1)
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

    screens = "Sources/Vitruvian/Core/AppKitExtensions.swift"
    bridge = "Sources/Vitruvian/Services/Switcher/SpaceWindowBridge.swift"
    write("PointerDisplayLookups.swift", "import AppKit\nimport Carbon.HIToolbox\nimport QuartzCore\n"
          + "extension PointerDisplayLookupContract.Screen {\n"
          + declaration(screens, "    static var withMouse:")
          + declaration(screens, "    static var withMenuBar:")
          + "}\nextension PointerDisplayLookupContract.Capturer {\n"
          + declaration("Sources/Vitruvian/Services/QuickTools/ScreenshotService.swift",
                        "    private func beginFullScreenCapture()").replace("private func", "func", 1)
          + "}\nextension PointerDisplayLookupContract.Bridge {\n"
          + "typealias Topology = VitruvianServices.SpaceWindowBridge.Topology\n"
          + declaration(bridge, "    static func visibleSpace(near")
          + "}\nextension PointerDisplayLookupContract.Layout {\n"
          + declaration("Sources/Vitruvian/Services/WindowLayout/WindowLayoutService.swift",
                        "    private func showDirectionalIndicator(").replace("private func", "func", 1)
          + "}\nextension PointerDisplayLookupContract.HUD {\n"
          + declaration("Sources/Vitruvian/Services/QuitProtection/QuitProtectionHUD.swift",
                        "    private func positionPanel(").replace("private func", "func", 1)
          + "}\nextension PointerDisplayLookupContract.Chooser {\n"
          + "".join(declaration(selection, prefix).replace("private func", "func", 1)
                    for prefix in ["    private func nudgePointer(", "    private func panelUnderMouse()"])
          + "}\nextension PointerDisplayLookupContract.Dock {\n"
          + declaration(dock, "    func endWindowDrag(")
          + "}\n")



if __name__ == "__main__":
    main()
