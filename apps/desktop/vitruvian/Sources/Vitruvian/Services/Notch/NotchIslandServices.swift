// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

import AppKit
import VitruvianCore

/// The services the island reads, starts, stops and asks to act.
/// `SystemNotchIslandServices` is the app's, the shared instances; a test can
/// stand in for any of them.
@MainActor
package protocol NotchIslandServices: AnyObject {
    // MARK: What the island reads

    var playback: NotchPlayback? { get }
    var artwork: NSImage? { get }
    var artworkTint: NotchArtworkTint? { get }
    var timerSession: NotchTimerSession { get }
    /// The timer's clock, which its session's readings count against.
    var timerNow: TimeInterval { get }
    var watchActive: Bool { get }
    var watchHeadline: String { get }
    var watchShowsThumbnail: Bool { get }
    var downloads: [NotchDownloadItem] { get }
    var choosingDownloadFolder: Bool { get }
    var agentUsage: AgentUsageSnapshot { get }
    var keepAwakeActive: Bool { get }
    var keepAwakeEndDate: Date? { get }
    var calendarCountdown: NotchCalendarCountdown? { get }
    /// The person chose to count down to this event.
    func calendarIsChosen(_ event: NotchCalendarEvent) -> Bool
    var importingLyrics: Bool { get }
    var scratchpadModal: Bool { get }
    var canCreatePad: Bool { get }
    var canClosePad: Bool { get }
    var keepsCalendarPrompt: Bool { get }
    var keepsCameraPrompt: Bool { get }
    var activeUtility: QuickLauncherItem? { get }
    var editingTools: Bool { get }
    var visibleTools: [QuickLauncherItem] { get }
    var mediaPresented: Bool { get }
    var mediaContentHeight: CGFloat? { get }
    var offersMediaDrop: Bool { get }
    var systemSnapshot: SystemSnapshot { get }
    var updateOffered: Bool { get }
    var openingNotification: UUID? { get }

    // MARK: What the island starts and stops

    func startMusic()
    func stopMusic()
    func syncTimer()
    func suspendTimer()
    func stopTimer()
    func syncWatch()
    func stopWatch()
    func syncDownloads()
    func stopDownloads()
    func syncCalendar()
    func stopCalendar()
    func syncNotifications()
    func stopNotifications()
    func syncAudioLevel()
    func stopAudioLevel()
    func syncAgentUsage()
    func pauseAgentUsage()
    func stopAgentUsage()
    func syncAccessories()
    func suspendAccessories()
    func stopAccessories()
    func syncFileTools()
    func stopFileTools()
    func stopLyrics()
    func hideCamera()
    func setMonitorDetailNeeds(_ needs: SystemMonitorPanelNeeds)
    func setMonitorVisible(_ visible: Bool)
    func syncLockScreen(_ session: NotchSessionState)
    func closeLockScreen()
    func playLockSound(locking: Bool)

    // MARK: What the island asks them to do

    func rememberPasteTarget()
    func prepareTools()
    /// Whether the tools page takes a key, after acting on it.
    func takesToolsKey(_ event: NSEvent, flow: QuickToolsSupport.GridFlow) -> Bool
    func createPad(defaultName: String)
    func showNormalMenuPanel()
    func skipTrack(forward: Bool)
    func openNotification(_ id: UUID,
                          completion: @escaping @MainActor @Sendable (NotchNotificationReader.ActionResult) -> Void)
    func dismissNotification(_ id: UUID)
    func toggleKeepAwake()
    func toggleMicrophone()
    func captureScreenshot()
    func toggleRecording()
    func showCommandBar()
    func showScratchpad()
    func openNotchSettings()
    func showSettingsModule(_ module: NotchModule)
}

/// The shared instances, as the app runs them.
@MainActor
package final class SystemNotchIslandServices: NotchIslandServices {
    package init() {}

    package var playback: NotchPlayback? { NotchMusicService.shared.playback }
    package var artwork: NSImage? { NotchMusicService.shared.artwork }
    package var artworkTint: NotchArtworkTint? { NotchMusicService.shared.artworkTint }
    package var timerSession: NotchTimerSession { NotchTimerService.shared.session }
    package var timerNow: TimeInterval { NotchTimerService.shared.now }
    package var watchActive: Bool { NotchWatchService.shared.isActive }
    package var watchHeadline: String { NotchWatchService.shared.headline }
    package var watchShowsThumbnail: Bool { NotchWatchService.shared.showsThumbnail }
    package var downloads: [NotchDownloadItem] { NotchDownloadService.shared.items }
    package var choosingDownloadFolder: Bool { NotchDownloadService.shared.isChoosingFolder }
    package var agentUsage: AgentUsageSnapshot { AgentUsageService.shared.snapshot }
    package var keepAwakeActive: Bool { KeepAwakeManager.shared.isActive }
    package var keepAwakeEndDate: Date? { KeepAwakeManager.shared.endDate }
    package var calendarCountdown: NotchCalendarCountdown? { NotchCalendarService.shared.countdown }
    package func calendarIsChosen(_ event: NotchCalendarEvent) -> Bool { NotchCalendarService.shared.isChosen(event) }
    package var importingLyrics: Bool { NotchLyricsService.shared.isImporting }
    package var scratchpadModal: Bool { ScratchpadService.shared.modalInteractionActive }
    package var canCreatePad: Bool { ScratchpadService.shared.canCreatePad }
    package var canClosePad: Bool { ScratchpadService.shared.canClosePad }
    package var keepsCalendarPrompt: Bool { Permissions.shared.keepsCalendarPrompt }
    package var keepsCameraPrompt: Bool { CameraPreviewService.shared.keepsNotchPermissionPrompt }
    package var activeUtility: QuickLauncherItem? { QuickLauncherService.shared.activeUtility }
    package var editingTools: Bool { QuickLauncherService.shared.isEditing }
    package var visibleTools: [QuickLauncherItem] { QuickLauncherService.shared.visibleItems }
    package var mediaPresented: Bool { NotchFileToolsService.shared.mediaPresented }
    package var mediaContentHeight: CGFloat? { NotchFileToolsService.shared.mediaContentHeight }
    package var offersMediaDrop: Bool { NotchFileToolsService.shared.offersMediaDrop }
    package var systemSnapshot: SystemSnapshot { SystemMonitor.shared.snapshot }
    package var updateOffered: Bool { UpdateService.shared.state.isOffer }
    package var openingNotification: UUID? { NotchNotificationService.shared.openingID }

    package func startMusic() { NotchMusicService.shared.start() }
    package func stopMusic() { NotchMusicService.shared.stop() }
    package func syncTimer() { NotchTimerService.shared.syncWithPreferences() }
    package func suspendTimer() { NotchTimerService.shared.suspend() }
    package func stopTimer() { NotchTimerService.shared.stop() }
    package func syncWatch() { NotchWatchService.shared.syncWithPreferences() }
    package func stopWatch() { NotchWatchService.shared.stop() }
    package func syncDownloads() { NotchDownloadService.shared.syncWithPreferences() }
    package func stopDownloads() { NotchDownloadService.shared.stop() }
    package func syncCalendar() { NotchCalendarService.shared.syncWithPreferences() }
    package func stopCalendar() { NotchCalendarService.shared.stop() }
    package func syncNotifications() { NotchNotificationService.shared.syncWithPreferences() }
    package func stopNotifications() { NotchNotificationService.shared.stop() }
    package func syncAudioLevel() { NotchAudioLevelService.shared.syncWithPreferences() }
    package func stopAudioLevel() { NotchAudioLevelService.shared.stop() }
    package func syncAgentUsage() { AgentUsageService.shared.syncWithPreferences() }
    package func pauseAgentUsage() { AgentUsageService.shared.pause() }
    package func stopAgentUsage() { AgentUsageService.shared.stop() }
    package func syncAccessories() { NotchAccessoryService.shared.syncWithPreferences() }
    package func suspendAccessories() { NotchAccessoryService.shared.suspend() }
    package func stopAccessories() { NotchAccessoryService.shared.stop() }
    package func syncFileTools() { NotchFileToolsService.shared.syncWithPreferences() }
    package func stopFileTools() { NotchFileToolsService.shared.stop() }
    package func stopLyrics() { NotchLyricsService.shared.stop() }
    package func hideCamera() { CameraPreviewService.shared.hideEmbedded() }
    package func setMonitorDetailNeeds(_ needs: SystemMonitorPanelNeeds) { SystemMonitor.shared.setNotchDetailNeeds(needs) }
    package func setMonitorVisible(_ visible: Bool) { SystemMonitor.shared.setNotchVisible(visible) }
    package func syncLockScreen(_ session: NotchSessionState) { NotchLockScreenService.shared.sync(session) }
    package func closeLockScreen() { NotchLockScreenService.shared.close() }
    package func playLockSound(locking: Bool) { NotchLockScreenService.shared.playSound(locking: locking) }

    package func rememberPasteTarget() { ClipboardHistoryService.shared.rememberPasteTarget() }
    package func prepareTools() { QuickLauncherService.shared.prepareForPresentation() }
    package func takesToolsKey(_ event: NSEvent, flow: QuickToolsSupport.GridFlow) -> Bool {
        QuickLauncherService.shared.takesPanelKey(event, flow: flow)
    }
    package func createPad(defaultName: String) { ScratchpadService.shared.createPad(defaultName: defaultName) }
    package func showNormalMenuPanel() { MenuPanelFocus.shared.showNormalPanel() }
    package func skipTrack(forward: Bool) { NotchMusicService.shared.skipFromGesture(forward: forward) }
    package func openNotification(_ id: UUID,
                                  completion: @escaping @MainActor @Sendable (NotchNotificationReader.ActionResult) -> Void) {
        NotchNotificationService.shared.open(id, completion: completion)
    }
    package func dismissNotification(_ id: UUID) { NotchNotificationService.shared.dismiss(id) }
    package func toggleKeepAwake() { KeepAwakeManager.shared.toggle() }
    package func toggleMicrophone() { MicMuteService.shared.toggle() }
    package func captureScreenshot() { ScreenshotService.shared.capture() }
    package func toggleRecording() { ScreenRecorderService.shared.toggle() }
    package func showCommandBar() { CommandBarService.shared.show() }
    package func showScratchpad() { ScratchpadService.shared.show() }
    package func openNotchSettings() { SettingsRouter.shared.request(FeatureSettingsDestination(.notch)) }
    package func showSettingsModule(_ module: NotchModule) { SettingsRouter.shared.notchModule = module }
}
