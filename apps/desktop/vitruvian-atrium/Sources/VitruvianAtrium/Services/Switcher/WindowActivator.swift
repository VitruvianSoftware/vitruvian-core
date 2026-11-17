// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import VitruvianAtriumCore
import VitruvianAtriumDesign

private let switcherAXPressedNotification = "AXPressed"

/// The source apps one activation is handed. The session source is the
/// window an App Switcher session opened over: it arms the minimize restore,
/// the Space hop and the staging behind the target. The handoff is the app a
/// caller saw in front, which only the delayed focus guards may treat as the
/// source.
package struct SwitcherActivationSources: Equatable {
    package var sourceWasFullscreen: Bool
    package var sourcePID: pid_t?
    package var handoffSourcePID: pid_t?
    package var sourceWindowID: CGWindowID?
    package var sourceWindowOwnerPID: pid_t?

    package init(sourceWasFullscreen: Bool = false,
                 sourcePID: pid_t? = nil,
                 handoffSourcePID: pid_t? = nil,
                 sourceWindowID: CGWindowID? = nil,
                 sourceWindowOwnerPID: pid_t? = nil) {
        self.sourceWasFullscreen = sourceWasFullscreen
        self.sourcePID = sourcePID
        self.handoffSourcePID = handoffSourcePID
        self.sourceWindowID = sourceWindowID
        self.sourceWindowOwnerPID = sourceWindowOwnerPID
    }

    /// What a session that opened over this window hands over, before the
    /// handoff is known. A fullscreen source owns its Space, so its window is
    /// never staged behind the target.
    package init(sessionPID: pid_t?, windowID: CGWindowID?, windowOwnerPID: pid_t?, isFullscreen: Bool) {
        self.init(sourceWasFullscreen: isFullscreen,
                  sourcePID: sessionPID,
                  sourceWindowID: isFullscreen ? nil : windowID,
                  sourceWindowOwnerPID: windowOwnerPID)
    }
}

/// Shared by the pending writes of one window selection. A later click or
/// keystroke belongs to the user even when no other VitruvianAtrium activation ran.
/// The queued work owns this guard; its monitors disappear with the last pass.
package final class SwitcherActivationWriteGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private var monitors: [Any] = []
    private let startedAt = ProcessInfo.processInfo.systemUptime

    package init() {
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observe(event)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observe(event)
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    package var isActive: Bool { lock.withLock { active } }

    package func invalidate() {
        lock.withLock { active = false }
    }

    private func observe(_ event: NSEvent) {
        guard event.timestamp > startedAt,
              let cgEvent = event.cgEvent,
              cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
                != Int64(ProcessInfo.processInfo.processIdentifier) else { return }
        // Ignore the event that selected the window and our own activation or
        // Space-travel events. Neither local nor global monitoring consumes input.
        invalidate()
    }

    deinit {
        let monitors = monitors
        if Thread.isMainThread {
            monitors.forEach(NSEvent.removeMonitor)
        } else {
            DispatchQueue.main.async { monitors.forEach(NSEvent.removeMonitor) }
        }
    }
}

/// Brings a switcher selection to the front: unminimizes if needed, makes the
/// exact window the app's focused/main Accessibility window and activates the
/// owning app. The initial exact-window path fronts the window synchronously,
/// then performs remote Accessibility focus off the keyboard callback.
package enum WindowActivator {
    private static let focusRetryDelay: TimeInterval = 0.12
    private static let fullscreenFocusRetryDelays: [TimeInterval] = [0.18, 0.38, 0.68]
    fileprivate static let activationAXQueue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.switcher-activation-ax",
                                                               qos: .userInitiated)
    /// Reads of another process run here. A read can wait for the whole
    /// Accessibility timeout of an app that does not answer, and it never
    /// changes what the user sees. Keeping it off the write lane is what stops
    /// a stalled read of the previous switch from standing in front of the
    /// next switch's first focus.
    ///
    /// The lane is serial on purpose. The observations of one activation have
    /// an order — the initial minimized observation answers before the passes
    /// that compare against it — and a serial lane keeps that order without
    /// a second mechanism. The price is that a stalled read holds up the next
    /// activation's observations, never its first focus.
    fileprivate static let activationObservationQueue = DispatchQueue(
        label: "com.vitruviansoftware.vitruvian.switcher-activation-observation",
        qos: .userInitiated)
    private static let activationMainQueue = DispatchQueue.main
    // Main thread only, like the activations and closes that set them.
    nonisolated(unsafe) private static var pendingMinimizeRestore: SwitcherWindowMinimizeRestore?
    nonisolated(unsafe) private static var pendingWindowClose: SwitcherPendingWindowClose?
    nonisolated(unsafe) private static var windowCloseGeneration: UInt64 = 0
    private static let activationLock = NSLock()
    // Both guarded by activationLock.
    nonisolated(unsafe) private static var activationGeneration: UInt64 = 0
    nonisolated(unsafe) private static var activationGenerationsByPID: [pid_t: UInt64] = [:]

    /// Runs one observation on the observation lane. The caller keeps the
    /// decision that follows on the main thread and the writes that follow
    /// the decision on the write lane.
    fileprivate static func runObservation(_ work: @escaping () -> Void) {
        // The work is handed over once and runs on the observation lane only.
        nonisolated(unsafe) let work = work
        activationObservationQueue.async { work() }
    }

    package static func activate(_ item: SwitcherItem,
                         retry: Bool = true,
                         sourceWasFullscreen: Bool = false,
                         sourcePID: pid_t? = nil,
                         handoffSourcePID: pid_t? = nil,
                         sourceWindowID: CGWindowID? = nil,
                         sourceWindowOwnerPID: pid_t? = nil,
                         windowServerSnapshot: SwitcherWindowServerSnapshot? = nil) {
        activate(item, retry: retry,
                 sources: SwitcherActivationSources(sourceWasFullscreen: sourceWasFullscreen,
                                                    sourcePID: sourcePID,
                                                    handoffSourcePID: handoffSourcePID,
                                                    sourceWindowID: sourceWindowID,
                                                    sourceWindowOwnerPID: sourceWindowOwnerPID),
                 windowServerSnapshot: windowServerSnapshot)
    }

    package static func activate(_ item: SwitcherItem, retry: Bool = true, sources: SwitcherActivationSources,
                                 windowServerSnapshot: SwitcherWindowServerSnapshot? = nil) {
        activate(item, retry: retry, sources: sources, windowServerSnapshot: windowServerSnapshot, steps: liveSteps)
    }

    /// The activation with its steps passed in. The session source, the
    /// window an App Switcher session opened over, arms the minimize restore,
    /// the Space hop and the staging behind the target. Only the delayed focus
    /// guards may treat a caller's handoff app as the source, and nothing here
    /// adopts the app in front on its own. `windowServerSnapshot` is the
    /// session's complete window-server metadata, which a current ID list can
    /// validate instead of reading every window again.
    package static func activate<App: SwitcherActivatableApp>(_ item: SwitcherItem,
                                                               retry: Bool = true,
                                                               sources: SwitcherActivationSources,
                                                               windowServerSnapshot: SwitcherWindowServerSnapshot? = nil,
                                                               steps: ActivationSteps<App>) {
        let sourceWasFullscreen = sources.sourceWasFullscreen
        let sourcePID = sources.sourcePID
        let generation = supersedePendingActivations(for: item.pid)
        // The source window is staged behind the target once per activation.
        // The state belongs to this generation: a later activation starts with
        // an unstaged source.
        let stagingState = SwitcherSourceStagingState(generation: generation)

        if item.pid == ProcessInfo.processInfo.processIdentifier {
            activateOwnWindow(item)
            return
        }

        guard let app = steps.calls.running(item.pid) else { return }
        // Only the delayed focus guards may treat a caller's handoff app as
        // the source. The minimize restore, source staging and Space hops stay
        // limited to the App Switcher session source.
        let retrySourcePID = SwitcherSupport.focusRetrySourcePID(
            sessionSourcePID: sourcePID,
            handoffSourcePID: sources.handoffSourcePID,
            targetPID: item.pid
        )
        let windowOwnerPID = item.windowOwnerPID

        // Unhiding an app that is not hidden still brings every one of its
        // windows forward (measured on macOS 27.2), so a window selection
        // raised its siblings before fronting the window (issue #1503).
        let appIsHidden = app.isHidden
        if appIsHidden { app.unhide() }
        let activationPlan = SwitcherSupport.activationPlan(
            targetsSpecificWindow: item.windowID != nil
        )
        guard let windowID = item.windowID else {
            let scheduleRetries: ((pid_t?, SwitcherActivationPlan, UInt64) -> Void)? = retry && sourceWasFullscreen
                ? steps.watchAppActivation(item.pid)
                : nil
            activateApp(app, plan: activationPlan, calls: steps.calls)
            steps.openApplication(app)
            scheduleRetries?(retrySourcePID, activationPlan, generation)
            return
        }
        // The list's own answer is a hint, not evidence. The state is read
        // fresh on every switch, including when the list already said the
        // window is minimized: the list was taken when the switch began, and
        // the user can have restored the window since. Only an answer that
        // came back "restored" can count as restored; a state neither source
        // can answer falls back to the list instead of becoming an answer.
        let itemReportedMinimized = item.isMinimized
        // One Accessibility element for the target window, shared by the
        // steps of this activation: the minimized-state read, the
        // minimize/restore observer and the window preparation all need the
        // very same window, and an app answers its window list once per
        // copy. The element is resolved for the exact window id and lives
        // inside this activation only.
        let targetWindow = SwitcherActivationTargetWindow(windowID: windowID) {
            steps.targetWindowElement(windowID, windowOwnerPID)
        }
        let liveMinimizedState: Bool?
        if let readTarget = steps.readTargetMinimizedState {
            liveMinimizedState = readTarget(targetWindow, windowOwnerPID)
        } else {
            liveMinimizedState = steps.minimizedState(windowID, windowOwnerPID)
        }
        let targetStartedMinimized = liveMinimizedState ?? itemReportedMinimized
        // A window parked on a Space that is not visible cannot be reached by
        // the Accessibility passes below; the hop travels there first and then
        // runs the same focus pass on arrival (issue #339). A minimized window
        // keeps its Accessibility element and can be deminiaturized directly
        // on the regular path without relying on Space shortcuts being enabled.
        let spaceHopStarted = !targetStartedMinimized
            && steps.beginSpaceHop(windowID, item.pid, windowOwnerPID, sourcePID, app)
        if spaceHopStarted {
            return
        }
        // Keep the baseline before prepare/front. A current all-ID query can
        // validate the earlier complete owner map without copying every
        // window's properties again. Any new ID or missing target falls back.
        let initialSnapshotTaken = retry || sourceWasFullscreen || item.isFullscreen
        var knownWindowIDs: Set<CGWindowID> = []
        var usedValidatedSnapshot = false
        if initialSnapshotTaken, !targetStartedMinimized,
           !sourceWasFullscreen, !item.isFullscreen,
           let windowServerSnapshot,
           let currentIDs = steps.currentWindowIDs(),
           let validated = windowServerSnapshot.activationWindowIDs(
               ownerPID: windowOwnerPID, targetWindowID: windowID,
               currentWindowIDs: currentIDs) {
            knownWindowIDs = validated
            usedValidatedSnapshot = true
        }
        if initialSnapshotTaken, !usedValidatedSnapshot {
            knownWindowIDs = steps.snapshot(windowOwnerPID)
        }
        let writeGuard = SwitcherActivationWriteGuard()
        let sourceReturn = SourceReturn(targetWindowID: windowID,
                                        targetPID: item.pid,
                                        targetWindowOwnerPID: windowOwnerPID,
                                        sourcePID: sourcePID,
                                        sourceWindowID: sources.sourceWindowID,
                                        sourceWindowOwnerPID: sources.sourceWindowOwnerPID,
                                        plan: activationPlan,
                                        generation: generation,
                                        writeGuard: writeGuard,
                                        stagingState: stagingState,
                                        targetWindow: targetWindow)
        let writeContext = ActivationWriteContext(generation: generation, writeGuard: writeGuard,
                                                  target: targetWindow)
        steps.watchTargetMinimize(sourceReturn)
        // Preparing a minimized window here would deminiaturize it while its
        // app is still in the background. The window server shows the
        // restoring window above the old app, then drops it beneath that app
        // again until activation, which reads as a flash. Leave the window
        // alone: the exact-window front below activates its app, and the
        // focus pass restores and focuses the window once the app is front.
        if !targetStartedMinimized {
            _ = steps.calls.prepare(windowID, windowOwnerPID, context: writeContext)
        }
        if sourceWasFullscreen || item.isFullscreen {
            let retryState = SwitcherWindowFocusRetryState(
                targetWindowID: windowID,
                targetStartedMinimized: targetStartedMinimized,
                targetWasObservedRestored: liveMinimizedState == false,
                knownWindowIDs: knownWindowIDs
            )
            scheduleInitialMinimizedStateObservation(retryState, windowID: windowID,
                                                     pid: windowOwnerPID, generation: generation, steps: steps)
            activateApp(app, plan: activationPlan, windowID: windowID, windowOwnerPID: windowOwnerPID,
                        calls: steps.calls, context: writeContext)
            let retryDelays = retry
                ? Self.fullscreenFocusRetryDelays
                : [Self.fullscreenFocusRetryDelays[0]]
            scheduleFocusRetries(sourceReturn,
                                 retrySourcePID: retrySourcePID,
                                 state: retryState,
                                 generation: generation,
                                 delays: retryDelays,
                                 stopsWhenTargetFocused: false,
                                 steps: steps)
            return
        }

        activateApp(app, plan: activationPlan, windowID: windowID, windowOwnerPID: windowOwnerPID,
                    calls: steps.calls, context: writeContext)
        // The first staging of an activation has nothing to skip yet, and no
        // foreground observation: the source app is the one in front.
        scheduleSourceStaging(sourceReturn, observedFrontmostPID: nil, steps: steps)

        guard retry else { return }
        let retryState = SwitcherWindowFocusRetryState(
            targetWindowID: windowID,
            targetStartedMinimized: targetStartedMinimized,
            targetWasObservedRestored: liveMinimizedState == false,
            knownWindowIDs: knownWindowIDs
        )
        scheduleInitialMinimizedStateObservation(retryState, windowID: windowID,
                                                 pid: windowOwnerPID, generation: generation, steps: steps)
        scheduleFocusRetries(sourceReturn,
                             retrySourcePID: retrySourcePID,
                             state: retryState,
                             generation: generation,
                             delays: [focusRetryDelay],
                             stopsWhenTargetFocused: true,
                             steps: steps)
    }

    package static func activate(pid: pid_t,
                         windowID: CGWindowID?,
                         appName: String,
                         retry: Bool = true,
                         handoffSourcePID: pid_t? = nil) {
        activate(pid: pid, windowID: windowID, appName: appName, retry: retry,
                 handoffSourcePID: handoffSourcePID, steps: liveSteps)
    }

    /// Activation by process, with its steps passed in. A caller that names
    /// an app this way has no switcher session behind it, so the app it saw
    /// in front is forwarded only as a focus handoff.
    package static func activate<App: SwitcherActivatableApp>(pid: pid_t,
                                                               windowID: CGWindowID?,
                                                               appName: String,
                                                               retry: Bool = true,
                                                               handoffSourcePID: pid_t? = nil,
                                                               steps: ActivationSteps<App>) {
        let item: SwitcherItem
        if let windowID {
            item = .window(id: windowID, title: appName, appName: appName,
                           pid: pid, isOnScreen: true, frame: .zero)
        } else {
            item = .appOnly(appName: appName, pid: pid)
        }
        activate(item, retry: retry, sources: SwitcherActivationSources(handoffSourcePID: handoffSourcePID),
                 steps: steps)
    }

    /// A selected window and the session source it was reached from: what the
    /// minimize restore watches, and what staging raises just behind it.
    package struct SourceReturn {
        package let targetWindowID: CGWindowID
        package let targetPID: pid_t
        package let targetWindowOwnerPID: pid_t
        package let sourcePID: pid_t?
        package let sourceWindowID: CGWindowID?
        package let sourceWindowOwnerPID: pid_t?
        package let plan: SwitcherActivationPlan
        /// The activation this selection belongs to, and what cancels its
        /// writes: a newer activation, or the user's own input since.
        package let generation: UInt64
        package let writeGuard: SwitcherActivationWriteGuard
        /// Whether the source window already sits behind the target.
        package let stagingState: SwitcherSourceStagingState
        /// The target window's Accessibility element, shared by the steps.
        package let targetWindow: SwitcherActivationTargetWindow
    }

    /// What a delayed focus pass asks before it brings the target forward
    /// again.
    package struct FocusRetryCheck {
        package let windowID: CGWindowID
        package let targetPID: pid_t
        package let targetWindowOwnerPID: pid_t
        /// The app whose return to the front ends the retries.
        package let sourcePID: pid_t?
        package let state: SwitcherWindowFocusRetryState
        /// Judges the app's own focus rather than who is in front.
        package var ignoresForeground = false
        package var stopsWhenTargetFocused = false
        /// What the pass already read on the observation lane. Without it the
        /// check reads for itself, as a Space hop's pass does.
        package var readings: FocusRetryReadings?
        package var frontmostPID: pid_t?
        /// The foreground read again after the focus query, so a slow query
        /// cannot reclaim an app the user has left.
        package var frontmostAfterFocusQueryPID: (() -> pid_t?)?
    }

    /// The steps an activation takes, each handed what it acts on. `live`
    /// acts on real apps and windows; tests pass doubles that record what
    /// each step was handed, chiefly which source app.
    package struct ActivationSteps<App: SwitcherActivatableApp> {
        package var calls: ActivationCalls<App>
        /// Opens the app's bundle without activating it, so an app with no
        /// window open gets one.
        package var openApplication: (App) -> Void
        /// Starts watching for the app to come forward, before it is asked
        /// to; the call it returns schedules the retries once it was.
        package var watchAppActivation: (_ targetPID: pid_t)
            -> (_ sourcePID: pid_t?, _ plan: SwitcherActivationPlan, _ generation: UInt64) -> Void
        package var minimizedState: (_ windowID: CGWindowID, _ pid: pid_t) -> Bool?
        /// Hands the activation to a Space hop when the window sits on a
        /// hidden Space; false when the regular path goes on.
        package var beginSpaceHop: (_ windowID: CGWindowID, _ appPID: pid_t, _ windowOwnerPID: pid_t,
                                    _ sourcePID: pid_t?, _ app: App) -> Bool
        /// Every window the owner has, in the scope the retry guard compares.
        package var snapshot: (_ ownerPID: pid_t) -> Set<CGWindowID>
        package var watchTargetMinimize: (SourceReturn) -> Void
        package var stageSourceBehindTarget: (SourceReturn) -> Void
        package var shouldContinueFocusRetry: (FocusRetryCheck) -> Bool
        /// Runs a delayed focus pass on the main thread.
        package var after: (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void
        /// Reads of another process run here, off the main thread, and never
        /// change what the user sees.
        package var observe: (_ work: @escaping () -> Void) -> Void
        /// The app in front now.
        package var frontmostPID: () -> pid_t?
        /// What a delayed pass reads of the target's app before it decides.
        package var readFocusRetryReadings: (_ windowID: CGWindowID, _ ownerPID: pid_t) -> FocusRetryReadings
        /// The window the app reports as focused, read after the first readings
        /// asked for it.
        package var focusedWindowID: (_ ownerPID: pid_t, _ windowID: CGWindowID, _ generation: UInt64) -> CGWindowID?
        /// Every window ID the window server lists now, or nil when it cannot say.
        package var currentWindowIDs: () -> Set<CGWindowID>?
        /// The Accessibility element of one window, resolved for the exact id.
        package var targetWindowElement: (_ windowID: CGWindowID, _ ownerPID: pid_t) -> AXUIElement?
        /// The target's minimized state read through the activation's shared
        /// element. Nil keeps `minimizedState`.
        package var readTargetMinimizedState: ((_ target: SwitcherActivationTargetWindow, _ pid: pid_t) -> Bool?)?

        package init(calls: ActivationCalls<App>,
                     openApplication: @escaping (App) -> Void,
                     watchAppActivation: @escaping (_ targetPID: pid_t)
                         -> (_ sourcePID: pid_t?, _ plan: SwitcherActivationPlan, _ generation: UInt64) -> Void,
                     minimizedState: @escaping (_ windowID: CGWindowID, _ pid: pid_t) -> Bool?,
                     beginSpaceHop: @escaping (_ windowID: CGWindowID, _ appPID: pid_t, _ windowOwnerPID: pid_t,
                                               _ sourcePID: pid_t?, _ app: App) -> Bool,
                     snapshot: @escaping (_ ownerPID: pid_t) -> Set<CGWindowID>,
                     watchTargetMinimize: @escaping (SourceReturn) -> Void,
                     stageSourceBehindTarget: @escaping (SourceReturn) -> Void,
                     shouldContinueFocusRetry: @escaping (FocusRetryCheck) -> Bool,
                     after: @escaping (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void,
                     observe: @escaping (_ work: @escaping () -> Void) -> Void = { $0() },
                     frontmostPID: @escaping () -> pid_t? = { nil },
                     readFocusRetryReadings: @escaping (_ windowID: CGWindowID, _ ownerPID: pid_t) -> FocusRetryReadings
                         = { _, _ in FocusRetryReadings(minimizedState: nil, targetWindowIDs: [], focusedWindowID: nil) },
                     focusedWindowID: @escaping (_ ownerPID: pid_t, _ windowID: CGWindowID, _ generation: UInt64)
                         -> CGWindowID? = { _, _, _ in nil },
                     currentWindowIDs: @escaping () -> Set<CGWindowID>? = { nil },
                     targetWindowElement: @escaping (_ windowID: CGWindowID, _ ownerPID: pid_t) -> AXUIElement?
                         = { _, _ in nil },
                     readTargetMinimizedState: ((_ target: SwitcherActivationTargetWindow, _ pid: pid_t) -> Bool?)?
                         = nil) {
            self.calls = calls
            self.openApplication = openApplication
            self.watchAppActivation = watchAppActivation
            self.minimizedState = minimizedState
            self.beginSpaceHop = beginSpaceHop
            self.snapshot = snapshot
            self.watchTargetMinimize = watchTargetMinimize
            self.stageSourceBehindTarget = stageSourceBehindTarget
            self.shouldContinueFocusRetry = shouldContinueFocusRetry
            self.after = after
            self.observe = observe
            self.frontmostPID = frontmostPID
            self.readFocusRetryReadings = readFocusRetryReadings
            self.focusedWindowID = focusedWindowID
            self.currentWindowIDs = currentWindowIDs
            self.targetWindowElement = targetWindowElement
            self.readTargetMinimizedState = readTargetMinimizedState
        }
    }

    private static var liveSteps: ActivationSteps<NSRunningApplication> {
        ActivationSteps(
            calls: liveActivation,
            openApplication: { app in
                guard let bundleURL = app.bundleURL else { return }
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.addsToRecentItems = false
                configuration.promptsUserIfNeeded = false
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            },
            watchAppActivation: { targetPID in
                let state = SwitcherAppActivationRetryState(targetPID: targetPID)
                return { sourcePID, plan, generation in
                    scheduleAppActivationRetries(targetPID: targetPID,
                                                 sourcePID: sourcePID,
                                                 plan: plan,
                                                 state: state,
                                                 generation: generation,
                                                 delays: Self.fullscreenFocusRetryDelays)
                }
            },
            minimizedState: { windowMinimizedState(windowID: $0, pid: $1) },
            beginSpaceHop: { SpaceHop.beginIfNeeded(windowID: $0, appPID: $1, windowOwnerPID: $2,
                                                    sourcePID: $3, app: $4) },
            snapshot: { windowIDs(ownerPID: $0) },
            watchTargetMinimize: { watchTargetMinimizeIfNeeded($0) },
            stageSourceBehindTarget: { sourceReturn in
                let outcome = stageSourceBehindTargetIfNeeded(sourceReturn)
                sourceReturn.stagingState.record(outcome, generation: sourceReturn.generation)
            },
            shouldContinueFocusRetry: { shouldContinueFocusRetry($0) },
            after: { delay, work in
                // Every pass is scheduled and run on the main thread.
                nonisolated(unsafe) let work = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
            },
            observe: { runObservation($0) },
            frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            readFocusRetryReadings: { readFocusRetryReadings(windowID: $0, targetWindowOwnerPID: $1) },
            focusedWindowID: { readFocusRetryFocusedWindowID(ownerPID: $0, targetWindowID: $1, generation: $2) },
            currentWindowIDs: { SpaceWindowBridge.allWindowIDs() },
            targetWindowElement: { targetWindowElement(windowID: $0, pid: $1) },
            readTargetMinimizedState: { activationMinimizedState(target: $0, pid: $1).state })
    }

    /// Why a focused-window read ended the way it did. The Accessibility
    /// error is the one the read already produced, so naming it costs no
    /// extra query.
    private enum FocusedWindowOutcome {
        /// No query was made: the process is not trusted for Accessibility.
        case notReadUntrusted
        /// The query was made and the app answered with an error.
        case readFailed
        /// The query succeeded and the app reported no focused window.
        case noFocusedWindow
        /// The app reported a focused element that names no window.
        case noWindowID
        /// The query succeeded and named a window.
        case focusedWindow
    }

    private struct FocusedWindowReading {
        let windowID: CGWindowID?
        let axError: AXError?
        let outcome: FocusedWindowOutcome
    }

    package static func focusedWindowID(for pid: pid_t) -> CGWindowID? {
        focusedWindowReading(for: pid).windowID
    }

    /// The single focused-window read every caller shares. It keeps the
    /// Accessibility error and the reason a read came back empty, so a log
    /// can report what was observed without asking the app a second time.
    private static func focusedWindowReading(for pid: pid_t) -> FocusedWindowReading {
        guard AXIsProcessTrusted() else {
            return FocusedWindowReading(windowID: nil, axError: nil, outcome: .notReadUntrusted)
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success else {
            return FocusedWindowReading(windowID: nil, axError: result, outcome: .readFailed)
        }
        guard let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return FocusedWindowReading(windowID: nil, axError: result, outcome: .noFocusedWindow)
        }
        let window = value as! AXUIElement
        guard let windowID = AXWindowResolver.windowID(for: window) else {
            return FocusedWindowReading(windowID: nil, axError: result, outcome: .noWindowID)
        }
        return FocusedWindowReading(windowID: windowID, axError: result, outcome: .focusedWindow)
    }

    package static func windowIsMinimized(windowID: CGWindowID,
                                          pid: pid_t) -> Bool {
        windowMinimizedState(windowID: windowID, pid: pid) == true
    }

    /// Undo only a verified work-area constraint from the preview's Dock hold.
    package static func restoreFrameAfterDockHold(_ item: SwitcherItem, original: CGRect,
                                         heldVisibleFrame: CGRect) {
        guard Permissions.accessibilityGranted, let windowID = item.windowID else { return }
        let app = AXUIElementCreateApplication(item.windowOwnerPID)
        AXUIElementSetMessagingTimeout(app, 0.35)
        guard let window = axElement(windowID: windowID, in: app, pid: item.windowOwnerPID),
              !boolAttribute(window, "AXFullScreen", default: true),
              minimizedState(of: window) == false else { return }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              DockPreviewFrameSupport.wasConstrained(CGRect(origin: origin, size: size),
                                                     original: original, visibleFrame: heldVisibleFrame)
        else { return }
        origin = original.origin
        size = original.size
        guard let position = AXValueCreate(.cgPoint, &origin),
              let dimensions = AXValueCreate(.cgSize, &size) else { return }
        let suspension = EnhancedUserInterfaceSuspension.suspend(forAppOf: window)
        defer { suspension?.resume() }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
    }

    /// The Accessibility element of one window of an app, resolved for the
    /// exact window id.
    ///
    /// The list read keeps the 350 ms the rest of the activation path uses.
    /// A shorter bound made a slow app give up on the shared resolution and
    /// then pay the same wait again when preparation asked for the list a
    /// second time, so the element is resolved once at this timeout instead.
    private static func targetWindowElement(windowID: CGWindowID,
                                            pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        // Observation runs before a hop and on every focus retry. Leave the
        // remote scan to an explicit window action instead of repeating it here.
        return axElement(windowID: windowID,
                         in: axApp)
    }

    /// The fresh minimized state of an activation target, and where it came
    /// from.
    ///
    /// The window server answers this without the other app's help, so an
    /// ordinary target never waits on the Accessibility of an app that is busy
    /// answering something else. That read used to hold the main thread for
    /// as long as the app took, which was the longest wait between the
    /// release of the shortcut and the first focus. When the window server has
    /// no answer the app's own Accessibility still reads the state, with its
    /// permission and unresolved semantics unchanged: an answer that cannot
    /// be resolved stays unknown. The state is always read fresh, never taken
    /// from the switcher's own older item.
    package static func activationMinimizedState(target: SwitcherActivationTargetWindow,
                                         pid: pid_t)
        -> (state: Bool?, source: SwitcherMinimizedStateSource) {
        if let state = SpaceWindowBridge.minimizedState(of: target.windowID) {
            return (state, .windowServer)
        }
        let reading = windowMinimizedState(target: target, pid: pid)
        return (reading.state, .accessibility)
    }

    /// Three-state minimized check for callers that must distinguish a window
    /// reported as restored from one that could not be resolved or queried.
    package static func windowMinimizedState(windowID: CGWindowID,
                                             pid: pid_t) -> Bool? {
        let target = SwitcherActivationTargetWindow(windowID: windowID) {
            targetWindowElement(windowID: windowID,
                                pid: pid)
        }
        return windowMinimizedState(target: target, pid: pid).state
    }

    /// The same check for a target whose element is shared with the other
    /// steps of the same activation. The window lookup and the attribute
    /// read are timed apart, so a slow answer is told apart from a slow list
    /// and a slow id lookup.
    package static func windowMinimizedState(target: SwitcherActivationTargetWindow,
                                     pid: pid_t)
        -> (state: Bool?, element: AXUIElement?) {
        guard Permissions.accessibilityGranted else { return (nil, nil) }
        guard let axWindow = target.element() else {
            return (nil, nil)
        }
        let state = minimizedState(of: axWindow)
        return (state, axWindow)
    }

    /// Moves a window's top-left corner to a global Accessibility point.
    ///
    /// Our own windows are refused rather than special-cased: reading this
    /// process's own Accessibility tree from the main thread is the one call
    /// that can deadlock, and Vitruvian Atrium has no Dock icon to drag a preview
    /// from in the first place.
    @discardableResult
    package static func setWindowOrigin(_ origin: CGPoint, windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.accessibilityGranted,
              pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp, pid: pid) else { return false }
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, value) == .success
    }

    /// Puts a window where a drag dropped it. Every window takes the same four
    /// steps in the same order whatever state it was in, because a drop that
    /// stops to check on a minimized window feels like a different gesture from
    /// a drop that does not. Un-minimizing a window that is already out returns
    /// immediately, so the step costs one attribute read.
    ///
    /// The position goes on before the window is restored: the restore then
    /// ends at the drop point rather than flying to the window's old place.
    @discardableResult
    package static func place(_ item: SwitcherItem, origin: CGPoint, pointer: CGPoint) -> Bool {
        guard Permissions.accessibilityGranted else { return false }
        return place(item, origin: origin, pointer: pointer, calls: livePlacement)
    }

    /// What placing a dropped window asks of the system. `live` moves real
    /// windows; tests pass doubles that record the steps instead.
    package struct PlacementCalls {
        package var unhideApp: (_ pid: pid_t) -> Void
        package var setOrigin: (_ origin: CGPoint, _ windowID: CGWindowID, _ pid: pid_t) -> Bool
        package var moveToVisibleSpace: (_ windowID: CGWindowID, _ pointer: CGPoint) -> Void
        package var restore: (_ windowID: CGWindowID, _ pid: pid_t) -> Void

        package init(unhideApp: @escaping (_ pid: pid_t) -> Void,
                     setOrigin: @escaping (_ origin: CGPoint, _ windowID: CGWindowID, _ pid: pid_t) -> Bool,
                     moveToVisibleSpace: @escaping (_ windowID: CGWindowID, _ pointer: CGPoint) -> Void,
                     restore: @escaping (_ windowID: CGWindowID, _ pid: pid_t) -> Void) {
            self.unhideApp = unhideApp
            self.setOrigin = setOrigin
            self.moveToVisibleSpace = moveToVisibleSpace
            self.restore = restore
        }
    }

    private static var livePlacement: PlacementCalls {
        PlacementCalls(unhideApp: { _ = NSRunningApplication(processIdentifier: $0)?.unhide() },
                       setOrigin: { setWindowOrigin($0, windowID: $1, pid: $2) },
                       moveToVisibleSpace: { _ = SpaceWindowBridge.moveToVisibleSpace($0, near: $1) },
                       restore: { _ = setWindowMinimized(false, windowID: $0, pid: $1) })
    }

    /// The drop's steps with the system calls passed in. Whether the window is
    /// minimized is not asked: restoring one that is already out is a no-op.
    @discardableResult
    package static func place(_ item: SwitcherItem, origin: CGPoint, pointer: CGPoint,
                              calls: PlacementCalls) -> Bool {
        guard let windowID = item.windowID,
              item.windowOwnerPID != ProcessInfo.processInfo.processIdentifier
        else { return false }
        let pid = item.windowOwnerPID

        if item.isAppHidden {
            calls.unhideApp(item.pid)
        }
        let placed = calls.setOrigin(origin, windowID, pid)
        calls.moveToVisibleSpace(windowID, pointer)
        calls.restore(windowID, pid)
        return placed
    }

    /// Hands the keyboard to a window a drag just placed. Dropping a window
    /// somewhere is a request to use it, and the app-level activation that
    /// follows raises the app without saying which of its windows the user was
    /// pointing at.
    package static func focusPlacedWindow(_ item: SwitcherItem) {
        guard let windowID = item.windowID,
              item.windowOwnerPID != ProcessInfo.processInfo.processIdentifier
        else { return }
        SpaceWindowBridge.frontWindow(windowID, ownerPID: item.windowOwnerPID)
    }

    @discardableResult
    package static func setWindowMinimized(_ minimized: Bool, windowID: CGWindowID, pid: pid_t) -> Bool {
        if pid == ProcessInfo.processInfo.processIdentifier {
            // This app's own windows come from the Dock preview, on the main thread.
            return MainActor.assumeIsolated {
                guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return false }
                if minimized {
                    window.miniaturize(nil)
                } else {
                    window.deminiaturize(nil)
                }
                return true
            }
        }

        guard Permissions.accessibilityGranted else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp, pid: pid) else { return false }
        if minimizedState(of: axWindow) == minimized { return true }

        let setResult = AXUIElementSetAttributeValue(axWindow,
                                                     kAXMinimizedAttribute as CFString,
                                                     minimized ? kCFBooleanTrue : kCFBooleanFalse)
        if setResult == .success, minimizedState(of: axWindow) == minimized {
            return true
        }

        guard minimized else {
            return setResult == .success
        }
        guard let minimizeButton = elementAttribute(axWindow, kAXMinimizeButtonAttribute as String),
              boolAttribute(minimizeButton, kAXEnabledAttribute as String, default: true)
        else {
            return setResult == .success
        }
        return AXUIElementPerformAction(minimizeButton, kAXPressAction as CFString) == .success
            || setResult == .success
    }

    /// True means the close request was delivered or its response timed out;
    /// the window may remain open for a save dialog. Callers verify removal.
    package static func closeWindow(windowID: CGWindowID,
                            appPID: pid_t,
                            windowOwnerPID: pid_t) -> Bool {
        if appPID == ProcessInfo.processInfo.processIdentifier {
            // A close runs on the main thread.
            return MainActor.assumeIsolated {
                guard let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return false }
                window.close()
                return true
            }
        }

        guard Permissions.accessibilityGranted else { return false }
        let axApp = AXUIElementCreateApplication(windowOwnerPID)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = closableElement(windowID: windowID, in: axApp, pid: windowOwnerPID),
              let closeButton = elementAttribute(axWindow, kAXCloseButtonAttribute as String)
        else { return false }
        // AX timeouts belong to each object, not its children.
        AXUIElementSetMessagingTimeout(closeButton, 0.35)
        guard boolAttribute(closeButton, kAXEnabledAttribute as String, default: true) else { return false }

        // A close runs on the main thread.
        MainActor.assumeIsolated { AutoQuitService.shared.recordProgrammaticCloseRequest(pid: appPID) }
        let result = AXUIElementPerformAction(closeButton, kAXPressAction as CFString)
        // A save dialog may keep an action callback inside a modal loop until
        // it times out. The request can already have arrived; never press again
        // or leave fullscreen merely because its answer was cannotComplete.
        return result == .success || result == .cannotComplete
    }

    /// Reuse the shared resolver for published and hidden-Space windows,
    /// including fullscreen ones, without travelling first (issue #2708).
    private static func closableElement(windowID: CGWindowID, in axApp: AXUIElement, pid: pid_t) -> AXUIElement? {
        guard let window = axElement(windowID: windowID, in: axApp, pid: pid)
        else { return nil }
        AXUIElementSetMessagingTimeout(window, 0.35)
        return window
    }

    /// A fullscreen window keeps its close button disabled (measured on macOS
    /// 26.6). True when it was asked to leave fullscreen, so a close can follow.
    private static func leaveFullscreenToClose(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.accessibilityGranted else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = closableElement(windowID: windowID, in: axApp, pid: pid),
              boolAttribute(axWindow, "AXFullScreen", default: false)
        else { return false }
        return AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, kCFBooleanFalse) == .success
    }

    /// Keeps the regular close path immediate. A fullscreen window first leaves
    /// fullscreen, a hidden app is temporarily revealed, and a hidden-Space
    /// target the lookup missed reuses the verified Space hop; each path polls
    /// until Accessibility can close that exact window.
    package static func closeWindowIncludingHiddenState(_ item: SwitcherItem,
                                                completion: @escaping (Bool) -> Void) {
        windowCloseGeneration &+= 1
        let requestGeneration = windowCloseGeneration
        pendingWindowClose?.cancel()
        // Cancellation calls completion, which can start a newer request.
        guard windowCloseGeneration == requestGeneration,
              pendingWindowClose == nil, let windowID = item.windowID else {
            completion(false)
            return
        }
        let app = NSRunningApplication(processIdentifier: item.pid)
        let appNeedsReveal = item.isAppHidden || app?.isHidden == true
        let windowNeedsSpaceHop = SpaceWindowBridge.isParkedOnHiddenSpace(windowID)
        let observesCloseResult = appNeedsReveal || windowNeedsSpaceHop
        let generation = currentActivationGeneration()
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let foregroundWindowID = observesCloseResult ? foregroundPID.flatMap { focusedWindowID(for: $0) } : nil
        if closeWindow(windowID: windowID,
                       appPID: item.pid,
                       windowOwnerPID: item.windowOwnerPID) {
            if observesCloseResult {
                let pending = SwitcherPendingWindowClose(item: item,
                                                         restoresHiddenApp: false,
                                                         usesSpaceHop: false,
                                                         observesCloseResult: true,
                                                         closeWasRequested: true,
                                                         generation: generation,
                                                         foregroundPID: foregroundPID,
                                                         foregroundWindowID: foregroundWindowID,
                                                         completion: completion)
                pendingWindowClose = pending
                pending.start()
            } else {
                completion(true)
            }
            return
        }
        if leaveFullscreenToClose(windowID: windowID, pid: item.windowOwnerPID) {
            let pending = SwitcherPendingWindowClose(item: item,
                                                     restoresHiddenApp: false,
                                                     usesSpaceHop: false,
                                                     leavesFullscreen: true,
                                                     observesCloseResult: observesCloseResult,
                                                     generation: generation,
                                                     foregroundPID: foregroundPID,
                                                     foregroundWindowID: foregroundWindowID,
                                                     completion: completion)
            pendingWindowClose = pending
            pending.start()
            return
        }
        guard appNeedsReveal || windowNeedsSpaceHop else {
            completion(false)
            return
        }
        let pending = SwitcherPendingWindowClose(item: item,
                                                 restoresHiddenApp: appNeedsReveal,
                                                 usesSpaceHop: windowNeedsSpaceHop,
                                                 observesCloseResult: observesCloseResult,
                                                 generation: generation,
                                                 foregroundPID: foregroundPID,
                                                 foregroundWindowID: foregroundWindowID,
                                                 completion: completion)
        pendingWindowClose = pending
        pending.start()
    }

    @discardableResult
    fileprivate static func finishPendingWindowClose(_ pending: SwitcherPendingWindowClose,
                                                     success: Bool) -> Bool {
        guard pendingWindowClose === pending else { return false }
        let requestGeneration = windowCloseGeneration
        pendingWindowClose = nil
        if pending.usesSpaceHop {
            SpaceHop.cancelPending()
        }
        pending.finish(success: success)
        // Completion can start another close synchronously.
        return pendingWindowClose == nil && windowCloseGeneration == requestGeneration
    }

    fileprivate static func windowExistsForClose(windowID: CGWindowID, ownerPID: pid_t) -> Bool? {
        guard let raw = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]]
        else { return nil }
        return raw.contains {
            ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ownerPID
        }
    }

    /// An activation starts on the main thread, like the pending restore it cancels.
    private static func activateOwnWindow(_ item: SwitcherItem) {
        MainActor.assumeIsolated {
            guard let windowID = item.windowID,
                  let window = NSApp.windows.first(where: { $0.windowNumber == Int(windowID) }) else { return }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// What a step that writes to another app is told about its own
    /// cancellation: the activation it belongs to, and whether the user has
    /// acted since. A write whose context says it was overtaken is dropped.
    package struct ActivationWriteContext {
        package var generation: UInt64?
        package var writeGuard: SwitcherActivationWriteGuard?
        /// The target window's Accessibility element, shared by the steps of
        /// one activation.
        package var target: SwitcherActivationTargetWindow?

        package init(generation: UInt64? = nil,
                     writeGuard: SwitcherActivationWriteGuard? = nil,
                     target: SwitcherActivationTargetWindow? = nil) {
            self.generation = generation
            self.writeGuard = writeGuard
            self.target = target
        }

        package static var none: ActivationWriteContext { ActivationWriteContext() }

        /// False once a newer activation or the user's own input has
        /// overtaken the writes of this one. A context with neither is never
        /// overtaken, as before.
        package var isCurrent: Bool {
            (generation.map { WindowActivator.isCurrentActivation($0) } ?? true)
                && (writeGuard?.isActive ?? true)
        }
    }

    /// What activating an app asks of the system. `live` activates real apps
    /// and windows; tests pass doubles that activate and post nothing.
    package struct ActivationCalls<App: SwitcherActivatableApp> {
        package var running: (pid_t) -> App?
        /// Hands activation to the app, as macOS 14 asks.
        package var yield: (App) -> Void
        package var frontWindow: (_ windowID: CGWindowID, _ ownerPID: pid_t) -> Bool
        package var focusWindow: (_ windowID: CGWindowID, _ pid: pid_t, _ makeAppFrontmost: Bool) -> Bool
        package var prepareWindow: (_ windowID: CGWindowID, _ pid: pid_t) -> Bool
        /// The same two writes with their cancellation context. Nil keeps
        /// the plain call above, which is all a double needs.
        package var focusWindowGuarded: ((_ windowID: CGWindowID, _ pid: pid_t, _ makeAppFrontmost: Bool,
                                          _ context: ActivationWriteContext) -> Bool)?
        package var prepareWindowGuarded: ((_ windowID: CGWindowID, _ pid: pid_t,
                                            _ context: ActivationWriteContext) -> Bool)?
        /// Runs a write to another app's windows off the key callback.
        package var writeLane: (_ work: @escaping () -> Void) -> Void
        /// Hands a decision back to the main thread.
        package var mainLane: (_ work: @escaping () -> Void) -> Void
        /// Whether the target, or the app owning its window, is in front.
        package var isTargetFrontmost: (_ app: App, _ ownerPID: pid_t) -> Bool

        package init(running: @escaping (pid_t) -> App?,
                     yield: @escaping (App) -> Void,
                     frontWindow: @escaping (_ windowID: CGWindowID, _ ownerPID: pid_t) -> Bool,
                     focusWindow: @escaping (_ windowID: CGWindowID, _ pid: pid_t, _ makeAppFrontmost: Bool) -> Bool,
                     prepareWindow: @escaping (_ windowID: CGWindowID, _ pid: pid_t) -> Bool,
                     focusWindowGuarded: ((_ windowID: CGWindowID, _ pid: pid_t, _ makeAppFrontmost: Bool,
                                           _ context: ActivationWriteContext) -> Bool)? = nil,
                     prepareWindowGuarded: ((_ windowID: CGWindowID, _ pid: pid_t,
                                             _ context: ActivationWriteContext) -> Bool)? = nil,
                     writeLane: @escaping (_ work: @escaping () -> Void) -> Void = { $0() },
                     mainLane: @escaping (_ work: @escaping () -> Void) -> Void = { $0() },
                     isTargetFrontmost: @escaping (_ app: App, _ ownerPID: pid_t) -> Bool = { _, _ in true }) {
            self.running = running
            self.yield = yield
            self.frontWindow = frontWindow
            self.focusWindow = focusWindow
            self.prepareWindow = prepareWindow
            self.focusWindowGuarded = focusWindowGuarded
            self.prepareWindowGuarded = prepareWindowGuarded
            self.writeLane = writeLane
            self.mainLane = mainLane
            self.isTargetFrontmost = isTargetFrontmost
        }

        package func focus(_ windowID: CGWindowID, _ pid: pid_t, makeAppFrontmost: Bool,
                           context: ActivationWriteContext) -> Bool {
            if let focusWindowGuarded {
                return focusWindowGuarded(windowID, pid, makeAppFrontmost, context)
            }
            return focusWindow(windowID, pid, makeAppFrontmost)
        }

        package func prepare(_ windowID: CGWindowID, _ pid: pid_t, context: ActivationWriteContext) -> Bool {
            if let prepareWindowGuarded {
                return prepareWindowGuarded(windowID, pid, context)
            }
            return prepareWindow(windowID, pid)
        }
    }

    private static var liveActivation: ActivationCalls<NSRunningApplication> {
        ActivationCalls(
            running: { NSRunningApplication(processIdentifier: $0) },
            yield: { ActivationHandoff.yield(to: $0) },
            frontWindow: { SpaceWindowBridge.frontWindow($0, ownerPID: $1) },
            focusWindow: { focusWindow(windowID: $0, pid: $1, makeAppFrontmost: $2) },
            prepareWindow: { prepareWindowForActivation(windowID: $0, pid: $1) },
            focusWindowGuarded: { windowID, pid, makeAppFrontmost, context in
                focusWindow(windowID: windowID, pid: pid, makeAppFrontmost: makeAppFrontmost,
                            generation: context.generation, writeGuard: context.writeGuard)
            },
            prepareWindowGuarded: { windowID, pid, context in
                prepareWindowForActivation(windowID: windowID, pid: pid, generation: context.generation,
                                           writeGuard: context.writeGuard, target: context.target)
            },
            writeLane: { work in
                // The work is handed over once and runs on the write lane only.
                nonisolated(unsafe) let work = work
                activationAXQueue.async { work() }
            },
            mainLane: { work in
                nonisolated(unsafe) let work = work
                activationMainQueue.async { work() }
            },
            isTargetFrontmost: { app, ownerPID in isActivationTargetFrontmost(app, windowOwnerPID: ownerPID) })
    }

    private static func activateApp(_ app: NSRunningApplication,
                                    plan: SwitcherActivationPlan,
                                    windowID: CGWindowID? = nil,
                                    windowOwnerPID: pid_t? = nil,
                                    context: ActivationWriteContext = .none) {
        activateApp(app, plan: plan, windowID: windowID, windowOwnerPID: windowOwnerPID,
                    calls: liveActivation, context: context)
    }

    /// Prefer the selected window, but retain cooperative activation when the
    /// private request or the Accessibility raise cannot be delivered. An
    /// accessory window owner cannot supply its regular host's menu bar. For
    /// a guarded activation, remote focus runs off the key callback, and a
    /// write the user has overtaken is dropped.
    package static func activateApp<App: SwitcherActivatableApp>(_ app: App,
                                                                 plan: SwitcherActivationPlan,
                                                                 windowID: CGWindowID? = nil,
                                                                 windowOwnerPID: pid_t? = nil,
                                                                 calls: ActivationCalls<App>,
                                                                 context: ActivationWriteContext = .none) {
        let hasGeneration = context.generation != nil
        func isCurrent() -> Bool { context.isCurrent }
        func scheduleFocusWindow(windowID: CGWindowID,
                                 ownerPID: pid_t,
                                 fallsBackToCooperativeActivation: Bool) {
            calls.writeLane {
                guard isCurrent() else { return }
                let focused = calls.focus(windowID, ownerPID, makeAppFrontmost: false, context: context)
                guard !focused, fallsBackToCooperativeActivation, isCurrent() else { return }
                calls.mainLane {
                    guard isCurrent(), calls.isTargetFrontmost(app, ownerPID) else { return }
                    activateAppCooperatively(app, allWindows: false, calls: calls)
                }
            }
        }

        if case .exactWindow(let exactWindowID) = SwitcherSupport.appActivationRoute(plan: plan, windowID: windowID) {
            guard isCurrent() else { return }
            let ownerPID = windowOwnerPID ?? app.processIdentifier
            if ownerPID != app.processIdentifier {
                activateAppCooperatively(app, allWindows: false, calls: calls)
                guard isCurrent() else { return }
            }
            let fronted = calls.frontWindow(exactWindowID, ownerPID)
            // Calls without a cancellation generation retain their legacy synchronous behavior.
            if !hasGeneration {
                if fronted, calls.focusWindow(exactWindowID, ownerPID, false) { return }
                activateAppCooperatively(app, allWindows: false, calls: calls)
                if let windowID {
                    _ = calls.focusWindow(windowID, windowOwnerPID ?? app.processIdentifier, false)
                }
                return
            }
            guard isCurrent() else { return }
            if !fronted {
                activateAppCooperatively(app, allWindows: false, calls: calls)
            }
            scheduleFocusWindow(windowID: exactWindowID, ownerPID: ownerPID,
                                fallsBackToCooperativeActivation: fronted)
            return
        }

        activateAppCooperatively(app, allWindows: plan.activateAllWindows, calls: calls)
        guard let windowID else { return }
        if !hasGeneration {
            _ = calls.focusWindow(windowID, windowOwnerPID ?? app.processIdentifier, false)
            return
        }
        scheduleFocusWindow(windowID: windowID, ownerPID: windowOwnerPID ?? app.processIdentifier,
                            fallsBackToCooperativeActivation: false)
    }

    private static func activateAppCooperatively<App: SwitcherActivatableApp>(_ app: App,
                                                                              allWindows: Bool,
                                                                              calls: ActivationCalls<App>) {
        let options: NSApplication.ActivationOptions = allWindows ? [.activateAllWindows] : []
        calls.yield(app)
        // The first answer is kept as it is: the fallback only runs when the
        // first request was refused.
        if !app.activateFromCurrent(options: options) {
            app.activate(options: options)
        }
    }

    private static func isActivationTargetFrontmost(_ app: NSRunningApplication,
                                                    windowOwnerPID: pid_t) -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        if frontmost.processIdentifier == app.processIdentifier
            || frontmost.processIdentifier == windowOwnerPID {
            return true
        }
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return frontmost.bundleIdentifier == bundleIdentifier
    }

    static func supersedePendingActivations(for pid: pid_t) -> UInt64 {
        let generation = beginActivation(for: pid)
        cancelPendingMinimizeRestore()
        SpaceHop.cancelPending()
        return generation
    }

    private static func beginActivation(for pid: pid_t) -> UInt64 {
        activationLock.withLock {
            activationGeneration &+= 1
            activationGenerationsByPID[pid] = activationGeneration
            return activationGeneration
        }
    }

    fileprivate static func activationGeneration(for pid: pid_t) -> UInt64 {
        activationLock.withLock { activationGenerationsByPID[pid] ?? 0 }
    }

    fileprivate static func currentActivationGeneration() -> UInt64 {
        activationLock.withLock { activationGeneration }
    }

    static func isCurrentActivation(_ generation: UInt64) -> Bool {
        activationLock.withLock {
            SwitcherSupport.isCurrentActivationGeneration(
                generation,
                current: activationGeneration
            )
        }
    }

    /// The initial minimized-state observation of a retry state. The read
    /// runs on the observation lane; the answer lands in the state, which
    /// the retry passes consult.
    private static func scheduleInitialMinimizedStateObservation<App: SwitcherActivatableApp>(
        _ state: SwitcherWindowFocusRetryState,
        windowID: CGWindowID,
        pid: pid_t,
        generation: UInt64,
        steps: ActivationSteps<App>) {
        steps.observe {
            guard isCurrentActivation(generation) else { return }
            state.observeInitialMinimizedState {
                steps.minimizedState(windowID, pid)
            }
        }
    }

    /// Stages the source window behind the target on the write lane, unless
    /// an earlier pass already confirmed it there and the source has not come
    /// back to the front.
    private static func scheduleSourceStaging<App: SwitcherActivatableApp>(_ sourceReturn: SourceReturn,
                                                                          observedFrontmostPID: pid_t?,
                                                                          steps: ActivationSteps<App>) {
        // A confirmed staging already left the source window behind the
        // target. Staging it again asks both apps for their window list a
        // second time, and only a source that came back to the front is no
        // longer behind the target.
        guard !SwitcherSupport.shouldSkipSourceStaging(outcome: sourceReturn.stagingState.lastOutcome,
                                                       frontmostPID: observedFrontmostPID,
                                                       sourcePID: sourceReturn.sourcePID) else {
            return
        }
        let generation = sourceReturn.generation
        let writeGuard = sourceReturn.writeGuard
        steps.calls.writeLane {
            guard isCurrentActivation(generation), writeGuard.isActive else { return }
            steps.stageSourceBehindTarget(sourceReturn)
        }
    }

    /// What one delayed pass reads of the target's app before it decides.
    package struct FocusRetryReadings {
        package let minimizedState: Bool?
        package let targetWindowIDs: Set<CGWindowID>
        package let focusedWindowID: CGWindowID?

        package init(minimizedState: Bool?, targetWindowIDs: Set<CGWindowID>, focusedWindowID: CGWindowID?) {
            self.minimizedState = minimizedState
            self.targetWindowIDs = targetWindowIDs
            self.focusedWindowID = focusedWindowID
        }
    }

    private static func readFocusRetryReadings(windowID: CGWindowID,
                                               targetWindowOwnerPID: pid_t) -> FocusRetryReadings {
        let minimizedState = windowMinimizedState(windowID: windowID,
                                                  pid: targetWindowOwnerPID)
        let targetWindowIDs = windowIDs(ownerPID: targetWindowOwnerPID)
        return FocusRetryReadings(minimizedState: minimizedState,
                                  targetWindowIDs: targetWindowIDs,
                                  focusedWindowID: nil)
    }

    private static func readFocusRetryFocusedWindowID(ownerPID: pid_t,
                                                      targetWindowID: CGWindowID?,
                                                      generation: UInt64?) -> CGWindowID? {
        focusedWindowReading(for: ownerPID).windowID
    }

    private static func needsFocusedWindowRead(targetPID: pid_t,
                                               sourcePID: pid_t?,
                                               targetWindowOwnerPID: pid_t,
                                               frontmostPID: pid_t?,
                                               readings: FocusRetryReadings,
                                               state: SwitcherWindowFocusRetryState,
                                               ignoresForeground: Bool = false,
                                               stopsWhenTargetFocused: Bool = false) -> Bool {
        let effectiveFrontmostPID = frontmostPID == targetWindowOwnerPID
            ? targetPID
            : frontmostPID
        // A minimized target only skips the focused-window read while its
        // restoration is still unconfirmed. Once this pass reads the window as
        // restored, it is treated like any other target: read the focused
        // window so the delayed pass can stand down instead of raising an
        // already focused window a second time.
        let minimizedStillRestoring = state.targetStartedMinimized
            && readings.minimizedState != false
        if stopsWhenTargetFocused,
           !ignoresForeground,
           !minimizedStillRestoring,
           effectiveFrontmostPID == targetPID {
            return true
        }
        var focusedWindowWasConsumed = false
        func noteFocusedWindowConsumption() -> CGWindowID? {
            focusedWindowWasConsumed = true
            return nil
        }
        _ = SwitcherSupport.shouldContinueFocusRetry(
            targetPID: targetPID,
            sourcePID: sourcePID,
            frontmostPID: effectiveFrontmostPID,
            targetIsMinimized: readings.minimizedState == true,
            targetStartedMinimized: state.targetStartedMinimized,
            targetWasObservedRestored: state.targetWasObservedRestored,
            knownWindowIDs: state.knownWindowIDs,
            targetAppWindowIDs: readings.targetWindowIDs,
            targetAppFocusedWindowID: noteFocusedWindowConsumption(),
            ignoresForeground: ignoresForeground
        )
        return focusedWindowWasConsumed
    }

    /// The delayed focus passes after an activation. Each asks the guard
    /// with the retry source, which may be a caller's handoff app, and stages
    /// only the session source behind the target.
    ///
    /// A pass reads on the observation lane, decides on the main thread and
    /// writes on the write lane, and a write is dropped once a newer
    /// activation or the user's own input has overtaken it. Every delay
    /// stays anchored to the chain's first schedule time.
    private static func scheduleFocusRetries<App: SwitcherActivatableApp>(_ sourceReturn: SourceReturn,
                                                                          retrySourcePID: pid_t?,
                                                                          state: SwitcherWindowFocusRetryState,
                                                                          generation: UInt64,
                                                                          delays: [TimeInterval],
                                                                          stopsWhenTargetFocused: Bool,
                                                                          steps: ActivationSteps<App>,
                                                                          scheduledAt: DispatchTime = .now(),
                                                                          delayIndex: Int = 0) {
        guard delays.indices.contains(delayIndex) else { return }
        let windowID = sourceReturn.targetWindowID
        let targetPID = sourceReturn.targetPID
        let targetWindowOwnerPID = sourceReturn.targetWindowOwnerPID
        let writeGuard = sourceReturn.writeGuard
        let context = ActivationWriteContext(generation: generation, writeGuard: writeGuard)
        let deadline = scheduledAt + delays[delayIndex]
        let nanosecondsLeft = Double(deadline.uptimeNanoseconds) - Double(DispatchTime.now().uptimeNanoseconds)
        let remaining = max(0, nanosecondsLeft) / 1_000_000_000
        steps.after(remaining) {
            // Retry state belongs to main. Stale passes never enter the AX queue.
            guard writeGuard.isActive, state.isActive, isCurrentActivation(generation) else { return }
            steps.observe {
                // The baseline this pass compares against was read on this
                // lane before the pass was queued, so the lane's order is the
                // join: the baseline has answered by the time this pass
                // looks at the owner's windows.
                guard isCurrentActivation(generation), writeGuard.isActive else { return }
                let readings = steps.readFocusRetryReadings(windowID, targetWindowOwnerPID)
                steps.calls.mainLane {
                    guard writeGuard.isActive, state.isActive, isCurrentActivation(generation) else { return }
                    let frontmostPID = steps.frontmostPID()
                    let needsFocusedWindow = needsFocusedWindowRead(
                        targetPID: targetPID,
                        sourcePID: retrySourcePID,
                        targetWindowOwnerPID: targetWindowOwnerPID,
                        frontmostPID: frontmostPID,
                        readings: readings,
                        state: state,
                        stopsWhenTargetFocused: stopsWhenTargetFocused)
                    func check(_ readings: FocusRetryReadings, _ frontmostPID: pid_t?,
                               _ frontmostAfterFocusQueryPID: (() -> pid_t?)? = nil) -> FocusRetryCheck {
                        FocusRetryCheck(windowID: windowID,
                                        targetPID: targetPID,
                                        targetWindowOwnerPID: targetWindowOwnerPID,
                                        sourcePID: retrySourcePID,
                                        state: state,
                                        stopsWhenTargetFocused: stopsWhenTargetFocused,
                                        readings: readings,
                                        frontmostPID: frontmostPID,
                                        frontmostAfterFocusQueryPID: frontmostAfterFocusQueryPID)
                    }
                    func continueWithReadings(_ finalReadings: FocusRetryReadings, _ initialFrontmostPID: pid_t?,
                                              _ postQueryFrontmostPID: (() -> pid_t?)?) {
                        guard steps.shouldContinueFocusRetry(check(finalReadings, initialFrontmostPID,
                                                                    postQueryFrontmostPID)) else {
                            writeGuard.invalidate()
                            return
                        }
                        guard writeGuard.isActive,
                              let app = steps.calls.running(targetPID),
                              !app.isTerminated else { return }
                        steps.calls.writeLane {
                            guard isCurrentActivation(generation), writeGuard.isActive else { return }
                            _ = steps.calls.prepare(windowID, targetWindowOwnerPID, context: context)
                            guard isCurrentActivation(generation), writeGuard.isActive else { return }
                            steps.calls.mainLane {
                                guard isCurrentActivation(generation), writeGuard.isActive else { return }
                                // One foreground sample decides this round and
                                // the source staging below, so the two cannot
                                // disagree about who is in front.
                                let observedFrontmostPID = steps.frontmostPID()
                                guard steps.shouldContinueFocusRetry(check(finalReadings, observedFrontmostPID)) else {
                                    writeGuard.invalidate()
                                    return
                                }
                                guard let app = steps.calls.running(targetPID), !app.isTerminated else { return }
                                activateApp(app, plan: sourceReturn.plan, windowID: windowID,
                                            windowOwnerPID: targetWindowOwnerPID,
                                            calls: steps.calls, context: context)
                                // The source window is only in front again when
                                // the user went back to it. The target's own
                                // activation in this round brought the target
                                // forward, so the source is behind it unless
                                // the observation above said otherwise.
                                scheduleSourceStaging(sourceReturn, observedFrontmostPID: observedFrontmostPID,
                                                      steps: steps)
                                scheduleFocusRetries(sourceReturn,
                                                     retrySourcePID: retrySourcePID,
                                                     state: state,
                                                     generation: generation,
                                                     delays: delays,
                                                     stopsWhenTargetFocused: stopsWhenTargetFocused,
                                                     steps: steps,
                                                     scheduledAt: scheduledAt,
                                                     delayIndex: delayIndex + 1)
                            }
                        }
                    }
                    guard needsFocusedWindow else {
                        continueWithReadings(readings, frontmostPID, nil)
                        return
                    }
                    steps.observe {
                        guard isCurrentActivation(generation), writeGuard.isActive else { return }
                        let focusedWindowID = steps.focusedWindowID(targetWindowOwnerPID, windowID, generation)
                        let finalReadings = FocusRetryReadings(
                            minimizedState: readings.minimizedState,
                            targetWindowIDs: focusedWindowID.map {
                                readings.targetWindowIDs.union([$0])
                            } ?? readings.targetWindowIDs,
                            focusedWindowID: focusedWindowID)
                        steps.calls.mainLane {
                            guard isCurrentActivation(generation), writeGuard.isActive, state.isActive else { return }
                            let postQueryFrontmostPID = steps.frontmostPID()
                            continueWithReadings(finalReadings, frontmostPID, { postQueryFrontmostPID })
                        }
                    }
                }
            }
        }
    }

    private static func scheduleAppActivationRetries(targetPID: pid_t,
                                                     sourcePID: pid_t?,
                                                     plan: SwitcherActivationPlan,
                                                     state: SwitcherAppActivationRetryState,
                                                     generation: UInt64,
                                                     delays: [TimeInterval]) {
        guard !delays.isEmpty else {
            state.invalidate()
            return
        }
        for (index, delay) in delays.enumerated() {
            let deadline = DispatchTime.now() + delay
            DispatchQueue.main.asyncAfter(deadline: deadline) {
                guard state.isActive else {
                    state.invalidate()
                    return
                }
                guard isCurrentActivation(generation) else {
                    state.invalidate()
                    return
                }
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                state.observe(frontmostPID: frontmostPID)
                guard SwitcherSupport.shouldContinueAppActivationRetry(
                    targetPID: targetPID,
                    sourcePID: sourcePID,
                    frontmostPID: frontmostPID,
                    targetWasObservedFrontmost: state.targetWasObservedFrontmost
                ) else {
                    state.invalidate()
                    return
                }
                guard let app = NSRunningApplication(processIdentifier: targetPID),
                      !app.isTerminated else {
                    state.invalidate()
                    return
                }
                activateApp(app, plan: plan)
                if index == delays.count - 1 {
                    state.invalidate()
                }
            }
        }
    }

    /// The one scope every focus-retry window list is taken in: the snapshot
    /// an activation or a hop takes and the live list each retry compares it
    /// against. All of the owner's windows, minimized, off-Space and
    /// auxiliary ones included. The on-screen list lags: a window the app has
    /// just opened is focused, and answered as focused by Accessibility,
    /// before the window server composites it, so an on-screen list compared
    /// against an all-windows snapshot reported nothing new in exactly the
    /// race the guard exists for.
    package static var focusWindowListScope: CGWindowListOption { .optionAll }

    private static func windowIDs(ownerPID: pid_t) -> Set<CGWindowID> {
        let raw = CGWindowListCopyWindowInfo(focusWindowListScope, kCGNullWindowID) as? [[String: Any]] ?? []
        return SwitcherSupport.focusRetryWindowIDs(in: raw, ownerPID: ownerPID)
    }

    private static func shouldContinueFocusRetry(_ check: FocusRetryCheck) -> Bool {
        if let readings = check.readings {
            return shouldContinueFocusRetry(windowID: check.windowID,
                                            targetPID: check.targetPID,
                                            targetWindowOwnerPID: check.targetWindowOwnerPID,
                                            sourcePID: check.sourcePID,
                                            state: check.state,
                                            readings: readings,
                                            frontmostPID: check.frontmostPID,
                                            frontmostAfterFocusQueryPID: check.frontmostAfterFocusQueryPID,
                                            ignoresForeground: check.ignoresForeground,
                                            stopsWhenTargetFocused: check.stopsWhenTargetFocused)
        }
        return shouldContinueFocusRetry(windowID: check.windowID,
                                 targetPID: check.targetPID,
                                 targetWindowOwnerPID: check.targetWindowOwnerPID,
                                 sourcePID: check.sourcePID,
                                 state: check.state,
                                 ignoresForeground: check.ignoresForeground,
                                 stopsWhenTargetFocused: check.stopsWhenTargetFocused)
    }

    private static func shouldContinueFocusRetry(windowID: CGWindowID,
                                                 targetPID: pid_t,
                                                 targetWindowOwnerPID: pid_t,
                                                 sourcePID: pid_t?,
                                                 state: SwitcherWindowFocusRetryState,
                                                 ignoresForeground: Bool = false,
                                                 stopsWhenTargetFocused: Bool = false,
                                                 generation: UInt64? = nil) -> Bool {
        guard state.isActive else { return false }
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var readings = readFocusRetryReadings(
            windowID: windowID,
            targetWindowOwnerPID: targetWindowOwnerPID)
        if needsFocusedWindowRead(
            targetPID: targetPID,
            sourcePID: sourcePID,
            targetWindowOwnerPID: targetWindowOwnerPID,
            frontmostPID: reportedFrontmostPID,
            readings: readings,
            state: state,
            ignoresForeground: ignoresForeground,
            stopsWhenTargetFocused: stopsWhenTargetFocused
        ) {
            readings = FocusRetryReadings(
                minimizedState: readings.minimizedState,
                targetWindowIDs: readings.targetWindowIDs,
                focusedWindowID: readFocusRetryFocusedWindowID(
                    ownerPID: targetWindowOwnerPID,
                    targetWindowID: windowID,
                    generation: generation
                )
            )
        }
        return shouldContinueFocusRetry(
            windowID: windowID,
            targetPID: targetPID,
            targetWindowOwnerPID: targetWindowOwnerPID,
            sourcePID: sourcePID,
            state: state,
            readings: readings,
            frontmostPID: reportedFrontmostPID,
            ignoresForeground: ignoresForeground,
            stopsWhenTargetFocused: stopsWhenTargetFocused)
    }

    private static func shouldContinueFocusRetry(windowID: CGWindowID,
                                                 targetPID: pid_t,
                                                 targetWindowOwnerPID: pid_t,
                                                 sourcePID: pid_t?,
                                                 state: SwitcherWindowFocusRetryState,
                                                 readings: FocusRetryReadings,
                                                 frontmostPID: pid_t?,
                                                 frontmostAfterFocusQueryPID: (() -> pid_t?)? = nil,
                                                 ignoresForeground: Bool = false,
                                                 stopsWhenTargetFocused: Bool = false) -> Bool {
        guard state.isActive else { return false }
        let effectiveFrontmostPID = frontmostPID == targetWindowOwnerPID
            ? targetPID
            : frontmostPID
        let shouldContinue = state.shouldContinue(
            targetPID: targetPID,
            sourcePID: sourcePID,
            frontmostPID: effectiveFrontmostPID,
            frontmostAfterFocusQueryPID: frontmostAfterFocusQueryPID.map { read in
                {
                    let postQueryPID = read()
                    return postQueryPID == targetWindowOwnerPID ? targetPID : postQueryPID
                }
            },
            targetMinimizedState: readings.minimizedState,
            targetAppWindowIDs: readings.targetWindowIDs,
            // Use the same all-windows scope as the snapshot. The on-screen
            // list can lag a new window that Accessibility already reports
            // as focused.
            targetAppFocusedWindowID: readings.focusedWindowID,
            targetWindowIsFocused: readings.focusedWindowID == windowID,
            stopsWhenTargetFocused: stopsWhenTargetFocused,
            ignoresForeground: ignoresForeground
        )
        return shouldContinue
    }

    private static func watchTargetMinimizeIfNeeded(_ sourceReturn: SourceReturn) {
        watchTargetMinimizeIfNeeded(windowID: sourceReturn.targetWindowID,
                                    targetPID: sourceReturn.targetPID,
                                    targetWindowOwnerPID: sourceReturn.targetWindowOwnerPID,
                                    sourcePID: sourceReturn.sourcePID,
                                    sourceWindowID: sourceReturn.sourceWindowID,
                                    sourceWindowOwnerPID: sourceReturn.sourceWindowOwnerPID,
                                    activationPlan: sourceReturn.plan,
                                    generation: sourceReturn.generation,
                                    targetWindow: sourceReturn.targetWindow)
    }

    private static func watchTargetMinimizeIfNeeded(windowID: CGWindowID,
                                                    targetPID: pid_t,
                                                    targetWindowOwnerPID: pid_t,
                                                    sourcePID: pid_t?,
                                                    sourceWindowID: CGWindowID?,
                                                    sourceWindowOwnerPID: pid_t?,
                                                    activationPlan: SwitcherActivationPlan,
                                                    generation: UInt64,
                                                    targetWindow: SwitcherActivationTargetWindow) {
        guard activationPlan.restoreSourceWhenTargetMinimizes,
              let sourcePID,
              SwitcherSupport.shouldRestoreSourceAfterTargetMinimize(targetPID: targetPID,
                                                                     sourcePID: sourcePID,
                                                                     frontmostPID: targetPID,
                                                                     targetIsMinimized: true)
        else {
            return
        }

        // The element is resolved here, after the guard, so a switch that
        // never installs the observer does not ask the app for its window
        // list at all.
        pendingMinimizeRestore = SwitcherWindowMinimizeRestore(windowID: windowID,
                                                               targetPID: targetPID,
                                                               targetWindowOwnerPID: targetWindowOwnerPID,
                                                               sourcePID: sourcePID,
                                                               sourceWindowID: sourceWindowID,
                                                               sourceWindowOwnerPID: sourceWindowOwnerPID,
                                                               generation: generation,
                                                               axWindow: targetWindow.element())
    }

    fileprivate static func cancelPendingMinimizeRestore() {
        pendingMinimizeRestore?.invalidate()
        pendingMinimizeRestore = nil
    }

    fileprivate static func cancelPendingMinimizeRestore(_ restore: SwitcherWindowMinimizeRestore) {
        guard pendingMinimizeRestore === restore else { return }
        cancelPendingMinimizeRestore()
    }

    fileprivate static func restoreSourceAfterTargetMinimizeIntent(_ restore: SwitcherWindowMinimizeRestore,
                                                                   keepPending: Bool = false,
                                                                   allowSystemPromotion: Bool = false) {
        guard pendingMinimizeRestore === restore,
              isCurrentActivation(restore.generation) else { return }
        let reportedFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let frontmostPID = reportedFrontmostPID == restore.targetWindowOwnerPID
            ? restore.targetPID
            : reportedFrontmostPID
        guard SwitcherSupport.shouldRestoreSourceAfterTargetMinimizeIntent(
                targetPID: restore.targetPID,
                sourcePID: restore.sourcePID,
                frontmostPID: frontmostPID,
                focusedWindowID: { () -> CGWindowID? in
                    let reading = focusedWindowReading(for: restore.targetWindowOwnerPID)
                    return reading.windowID
                }(),
                targetWindowID: restore.windowID,
                targetIsMinimized: windowIsMinimized(windowID: restore.windowID,
                                                     pid: restore.targetWindowOwnerPID),
                frontmostMatchesTargetBundle: restore.matchesTargetBundle(frontmostPID),
                frontmostCanBeSystemPromotion: allowSystemPromotion) else { return }
        guard activateSource(pid: restore.sourcePID,
                             windowID: restore.sourceWindowID,
                             windowOwnerPID: restore.sourceWindowOwnerPID,
                             generation: restore.generation) else {
            cancelPendingMinimizeRestore()
            return
        }

        if !keepPending {
            cancelPendingMinimizeRestore()
        }
    }

    @discardableResult
    private static func activateSource(pid: pid_t,
                                       windowID: CGWindowID?,
                                       windowOwnerPID: pid_t?,
                                       generation: UInt64? = nil) -> Bool {
        activateSource(pid: pid, windowID: windowID, windowOwnerPID: windowOwnerPID,
                       calls: liveActivation, generation: generation)
    }

    @discardableResult
    package static func activateSource<App: SwitcherActivatableApp>(pid: pid_t,
                                                                    windowID: CGWindowID?,
                                                                    windowOwnerPID: pid_t?,
                                                                    calls: ActivationCalls<App>,
                                                                    generation: UInt64? = nil) -> Bool {
        guard generation.map({ isCurrentActivation($0) }) ?? true,
              let sourceApp = calls.running(pid),
              !sourceApp.isTerminated else { return false }

        if sourceApp.isHidden { sourceApp.unhide() }
        if let windowID {
            _ = calls.prepare(windowID, windowOwnerPID ?? pid, context: ActivationWriteContext(generation: generation))
        }
        guard generation.map({ isCurrentActivation($0) }) ?? true else { return false }
        // A missing source window (including a fullscreen source) is still a
        // return gesture, not a request to raise every window of that app.
        activateApp(sourceApp,
                    plan: SwitcherSupport.activationPlan(targetsSpecificWindow: true),
                    windowID: windowID,
                    windowOwnerPID: windowOwnerPID ?? pid,
                    calls: calls,
                    context: ActivationWriteContext(generation: generation))
        return true
    }

    @discardableResult
    private static func prepareWindowForActivation(windowID: CGWindowID,
                                                   pid: pid_t,
                                                   generation: UInt64? = nil,
                                                   writeGuard: SwitcherActivationWriteGuard? = nil,
                                                   target: SwitcherActivationTargetWindow? = nil) -> Bool {
        func isCurrent() -> Bool {
            (generation.map { isCurrentActivation($0) } ?? true)
                && (writeGuard?.isActive ?? true)
        }
        guard isCurrent(), Permissions.accessibilityGranted else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        // The element this activation already resolved for the same window
        // is used as it is; a step that runs on its own resolves its own.
        // Asking the target object here keeps the resolution behind the
        // guards: a preparation that returns early never asks the app.
        let axWindow: AXUIElement
        if let providedWindow = target?.element() {
            guard isCurrent() else { return false }
            axWindow = providedWindow
        } else {
            // A preparation is an explicit window action, so the resolver may
            // look past the published list for a window the app does not
            // describe there.
            guard isCurrent(),
                  let resolved = axElement(windowID: windowID,
                                          in: axApp,
                                          pid: pid),
                  isCurrent() else {
                return false
            }
            axWindow = resolved
        }

        var minimized: CFTypeRef?
        let minimizedResult = AXUIElementCopyAttributeValue(
            axWindow, kAXMinimizedAttribute as CFString, &minimized)
        guard isCurrent() else { return false }
        if minimizedResult == .success, (minimized as? Bool) == true {
            AXUIElementSetAttributeValue(axWindow,
                                         kAXMinimizedAttribute as CFString,
                                         kCFBooleanFalse)
            guard isCurrent() else { return false }
        }
        AXUIElementSetAttributeValue(axApp,
                                     kAXMainWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axApp,
                                     kAXFocusedWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXMainAttribute as CFString,
                                     kCFBooleanTrue)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXFocusedAttribute as CFString,
                                     kCFBooleanTrue)
        guard isCurrent() else { return false }
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        return true
    }

    @discardableResult
    private static func stageSourceBehindTargetIfNeeded(_ sourceReturn: SourceReturn) -> SwitcherSourceStagingOutcome {
        stageSourceBehindTargetIfNeeded(targetWindowID: sourceReturn.targetWindowID,
                                        targetPID: sourceReturn.targetPID,
                                        targetWindowOwnerPID: sourceReturn.targetWindowOwnerPID,
                                        sourcePID: sourceReturn.sourcePID,
                                        sourceWindowID: sourceReturn.sourceWindowID,
                                        sourceWindowOwnerPID: sourceReturn.sourceWindowOwnerPID,
                                        activationPlan: sourceReturn.plan,
                                        generation: sourceReturn.generation,
                                        writeGuard: sourceReturn.writeGuard)
    }

    private static func stageSourceBehindTargetIfNeeded(targetWindowID: CGWindowID,
                                                        targetPID: pid_t,
                                                        targetWindowOwnerPID: pid_t,
                                                        sourcePID: pid_t?,
                                                        sourceWindowID: CGWindowID?,
                                                        sourceWindowOwnerPID: pid_t?,
                                                        activationPlan: SwitcherActivationPlan,
                                                        generation: UInt64,
                                                        writeGuard: SwitcherActivationWriteGuard? = nil) -> SwitcherSourceStagingOutcome {
        func isCurrent() -> Bool {
            isCurrentActivation(generation) && (writeGuard?.isActive ?? true)
        }
        guard isCurrent(),
              activationPlan.restoreSourceWhenTargetMinimizes,
              SwitcherSupport.shouldStageSourceBehindTarget(targetPID: targetPID,
                                                            sourcePID: sourcePID,
                                                            sourceWindowID: sourceWindowID),
              let sourcePID,
              let sourceWindowID,
              !SpaceWindowBridge.isParkedOnHiddenSpace(sourceWindowID),
              !SpaceWindowBridge.isParkedOnHiddenSpace(targetWindowID),
              Permissions.accessibilityGranted else {
            return .notApplicable
        }

        let sourceApp = AXUIElementCreateApplication(sourceWindowOwnerPID ?? sourcePID)
        let targetApp = AXUIElementCreateApplication(targetWindowOwnerPID)
        AXUIElementSetMessagingTimeout(sourceApp, 0.35)
        AXUIElementSetMessagingTimeout(targetApp, 0.35)
        guard isCurrent() else {
            return .unresolved
        }
        let sourceWindow = axElement(windowID: sourceWindowID,
                                     in: sourceApp)
        guard isCurrent() else {
            return .unresolved
        }
        guard let sourceWindow else {
            return .unresolved
        }
        let targetWindow = axElement(windowID: targetWindowID,
                                     in: targetApp)
        guard isCurrent() else {
            return .unresolved
        }
        guard let targetWindow else {
            return .unresolved
        }

        var sourceMinimized: CFTypeRef?
        let minimizedResult = AXUIElementCopyAttributeValue(
            sourceWindow, kAXMinimizedAttribute as CFString, &sourceMinimized)
        guard isCurrent() else {
            return .unresolved
        }
        // A minimized source window cannot sit behind the target yet. An
        // unreadable minimized state is not a minimized window, so the staging
        // still runs, but it cannot be confirmed either.
        if minimizedResult == .success, (sourceMinimized as? Bool) == true {
            return .sourceMinimized
        }

        // Do not pull the source back over an already-active target. Keep the
        // target raise below: foreground/focus alone does not prove it is onscreen.
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetIsFrontmost = frontmostPID == targetPID || frontmostPID == targetWindowOwnerPID
        if targetIsFrontmost,
           windowIsVisiblyFocused(windowID: targetWindowID,
                                  pid: targetWindowOwnerPID,
                                  window: targetWindow),
           isCurrent() {
            return minimizedResult == .success ? .staged : .unresolved
        }
        let sourceReady = targetIsFrontmost
            || AXUIElementPerformAction(sourceWindow, kAXRaiseAction as CFString) == .success
        guard isCurrent() else {
            return .unresolved
        }
        let targetRaiseResult = AXUIElementPerformAction(targetWindow, kAXRaiseAction as CFString)
        guard isCurrent() else {
            return .unresolved
        }
        let mainWindowResult = AXUIElementSetAttributeValue(targetApp,
                                                             kAXMainWindowAttribute as CFString,
                                                             targetWindow)
        guard isCurrent() else {
            return .unresolved
        }
        let focusedWindowResult = AXUIElementSetAttributeValue(targetApp,
                                                                kAXFocusedWindowAttribute as CFString,
                                                                targetWindow)
        guard isCurrent() else {
            return .unresolved
        }
        let windowMainResult = AXUIElementSetAttributeValue(targetWindow,
                                                             kAXMainAttribute as CFString,
                                                             kCFBooleanTrue)
        guard isCurrent() else {
            return .unresolved
        }
        let windowFocusedResult = AXUIElementSetAttributeValue(targetWindow,
                                                                kAXFocusedAttribute as CFString,
                                                                kCFBooleanTrue)
        guard isCurrent() else {
            return .unresolved
        }
        // Only confirmed source placement and target operations finish staging.
        // Otherwise the next retry pass stages it again.
        let staged = minimizedResult == .success
            && sourceReady
            && targetRaiseResult == .success
            && mainWindowResult == .success
            && focusedWindowResult == .success
            && windowMainResult == .success
            && windowFocusedResult == .success
        return staged ? .staged : .unresolved
    }

    private static func windowIsVisiblyFocused(windowID: CGWindowID,
                                               pid: pid_t,
                                               window: AXUIElement) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              minimizedState(of: window) == false,
              focusedWindowID(for: pid) == windowID,
              let onscreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                        kCGNullWindowID) as? [[String: Any]],
              let frontWindow = onscreen.first(where: {
                  ($0[kCGWindowLayer as String] as? Int) == 0
              }) else { return false }
        return (frontWindow[kCGWindowNumber as String] as? CGWindowID) == windowID
    }

    // AXMinimized changes at the start of the Dock animation. Its completion
    // notification is the boundary for focus writes, not that early state read.
    // Generated switcher passes wait on the AX lane, never the keyboard callback.
    // Unsupported/missing notifications retain the normal focus fallback.
    private static func restoreWindowBeforeFocus(_ window: AXUIElement,
                                                 pid: pid_t,
                                                 generation: UInt64?,
                                                 writeGuard: SwitcherActivationWriteGuard? = nil,
                                                 isCurrent externalIsCurrent: () -> Bool = { true }) -> Bool {
        func isCurrent() -> Bool {
            externalIsCurrent()
                && (generation.map { isCurrentActivation($0) } ?? true)
                && (writeGuard?.isActive ?? true)
        }
        guard isCurrent() else { return false }
        guard generation != nil else {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            return false
        }
        var observer: AXObserver?
        let created = AXObserverCreate(pid, { _, _, _, context in
            context?.assumingMemoryBound(to: Bool.self).pointee = true
        }, &observer)
        guard created == .success, let observer else {
            guard isCurrent() else { return false }
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            return false
        }
        var completed = false
        return withUnsafeMutablePointer(to: &completed) { completion in
            let notification = kAXWindowDeminiaturizedNotification as CFString
            guard AXObserverAddNotification(observer, window, notification, completion) == .success else {
                guard isCurrent() else { return false }
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                return false
            }
            let runLoop = CFRunLoopGetCurrent()
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            defer {
                CFRunLoopRemoveSource(runLoop, source, .defaultMode)
                AXObserverRemoveNotification(observer, window, notification)
            }
            guard isCurrent() else { return false }
            guard AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                               kCFBooleanFalse) == .success else { return false }
            let deadline = DispatchTime.now() + 0.5
            while !completion.pointee,
                  isCurrent(),
                  DispatchTime.now().uptimeNanoseconds < deadline.uptimeNanoseconds {
                CFRunLoopRunInMode(.defaultMode, 0.01, true)
            }
            return completion.pointee
        }
    }

    @discardableResult
    private static func focusWindow(windowID: CGWindowID,
                                    pid: pid_t,
                                    makeAppFrontmost: Bool = true,
                                    generation: UInt64? = nil,
                                    writeGuard: SwitcherActivationWriteGuard? = nil,
                                    isCurrent externalIsCurrent: () -> Bool = { true }) -> Bool {
        func isCurrent() -> Bool {
            externalIsCurrent()
                && (generation.map { isCurrentActivation($0) } ?? true)
                && (writeGuard?.isActive ?? true)
        }
        guard isCurrent(), Permissions.accessibilityGranted else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard isCurrent(),
              let axWindow = axElement(windowID: windowID,
                                      in: axApp,
                                      pid: pid),
              isCurrent() else {
            return false
        }

        var minimized: CFTypeRef?
        let minimizedResult = AXUIElementCopyAttributeValue(
            axWindow, kAXMinimizedAttribute as CFString, &minimized)
        guard isCurrent() else { return false }
        if minimizedResult == .success, (minimized as? Bool) == true {
            let completed = restoreWindowBeforeFocus(axWindow, pid: pid, generation: generation,
                                                    writeGuard: writeGuard, isCurrent: isCurrent)
            guard isCurrent() else { return false }
            if completed,
               windowIsVisiblyFocused(windowID: windowID, pid: pid, window: axWindow),
               isCurrent() {
                return true
            }
        }

        if makeAppFrontmost {
            AXUIElementSetAttributeValue(axApp,
                                         kAXFrontmostAttribute as CFString,
                                         kCFBooleanTrue)
            guard isCurrent() else { return false }
        }
        AXUIElementSetAttributeValue(axApp,
                                     kAXMainWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axApp,
                                     kAXFocusedWindowAttribute as CFString,
                                     axWindow)
        guard isCurrent() else { return false }
        let raised = AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXMainAttribute as CFString,
                                     kCFBooleanTrue)
        guard isCurrent() else { return false }
        AXUIElementSetAttributeValue(axWindow,
                                     kAXFocusedAttribute as CFString,
                                     kCFBooleanTrue)
        return isCurrent() && raised == .success
    }

    /// Ask the exact hidden-Space window to travel before application activation
    /// or synthetic input can select a sibling. Success acknowledges the raise;
    /// SpaceHop still verifies arrival and falls back if no travel takes place.
    static func raiseWindowOnHiddenSpace(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard Permissions.accessibilityGranted,
              pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return false }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        guard let axWindow = axElement(windowID: windowID, in: axApp, pid: pid) else { return false }
        AXUIElementSetMessagingTimeout(axWindow, 0.35)
        AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString) == .success
    }

    /// Every window the owner has right now, in the scope the retry guard
    /// compares against. Taken by a hop at the moment it begins.
    package static func focusSnapshot(ownerPID: pid_t) -> Set<CGWindowID> {
        windowIDs(ownerPID: ownerPID)
    }

    /// Focus pass run by SpaceHop once the target window's Space became
    /// visible and Accessibility can finally describe the window.
    ///
    /// Its pulses run up to a second after the switch, long enough for the
    /// user to open a window in the app they just reached — Command-N right
    /// after switching away from a fullscreen app lands here. They consult the
    /// same guard as every other delayed pass, so a window the app did not
    /// have when the hop began ends them instead of being covered.
    package static func focusAfterSpaceHop(windowID: CGWindowID,
                                   appPID: pid_t,
                                   windowOwnerPID: pid_t,
                                   sourcePID: pid_t?,
                                   state: SwitcherWindowFocusRetryState,
                                   writeGuard: SwitcherActivationWriteGuard? = nil) {
        focusAfterSpaceHop(windowID: windowID, appPID: appPID, windowOwnerPID: windowOwnerPID,
                           sourcePID: sourcePID, state: state, steps: liveSteps, writeGuard: writeGuard)
    }

    /// The hop's pass with its steps passed in.
    package static func focusAfterSpaceHop<App: SwitcherActivatableApp>(windowID: CGWindowID,
                                                                        appPID: pid_t,
                                                                        windowOwnerPID: pid_t,
                                                                        sourcePID: pid_t?,
                                                                        state: SwitcherWindowFocusRetryState,
                                                                        steps: ActivationSteps<App>,
                                                                        writeGuard: SwitcherActivationWriteGuard? = nil) {
        focusAfterSpaceHop(windowID: windowID,
                           appPID: appPID,
                           windowOwnerPID: windowOwnerPID,
                           // Travelling fronts whatever tops each desktop on the
                           // way, so this pass judges the app's own focus rather
                           // than who is in front.
                           shouldContinue: {
                               steps.shouldContinueFocusRetry(FocusRetryCheck(windowID: windowID,
                                                                              targetPID: appPID,
                                                                              targetWindowOwnerPID: windowOwnerPID,
                                                                              sourcePID: sourcePID,
                                                                              state: state,
                                                                              ignoresForeground: true))
                           },
                           calls: steps.calls,
                           writeGuard: writeGuard)
    }

    /// The same pass with its guard and its system calls passed in. The guard
    /// is asked before anything is brought forward. A hop that hands over its
    /// write guard also cancels with it: the pass stops once a newer
    /// activation or the user's own input has overtaken it.
    package static func focusAfterSpaceHop<App: SwitcherActivatableApp>(windowID: CGWindowID,
                                                                        appPID: pid_t,
                                                                        windowOwnerPID: pid_t,
                                                                        shouldContinue: () -> Bool,
                                                                        calls: ActivationCalls<App>,
                                                                        writeGuard: SwitcherActivationWriteGuard? = nil) {
        // The generation here is looked up by app, not handed over by the
        // hop: it is a fallback, and it is never the session's own number.
        let generation: UInt64? = writeGuard == nil ? nil : activationGeneration(for: appPID)
        let context = ActivationWriteContext(generation: generation, writeGuard: writeGuard)
        guard context.isCurrent,
              let app = calls.running(appPID), !app.isTerminated else { return }
        guard shouldContinue() else {
            writeGuard?.invalidate()
            return
        }
        _ = calls.prepare(windowID, windowOwnerPID, context: context)
        guard context.isCurrent else { return }
        activateApp(app,
                    plan: SwitcherSupport.activationPlan(targetsSpecificWindow: true),
                    windowID: windowID,
                    windowOwnerPID: windowOwnerPID,
                    calls: calls,
                    context: context)
    }

    /// Finds the Accessibility element of one window of an app.
    ///
    /// The shared resolver answers the published window list first and, when a
    /// pid is supplied, falls back to a bounded remote lookup for a window the
    /// app does not describe there. A caller that only observes never supplies
    /// the pid, so an observation does not pay for the remote scan.
    private static func axElement(windowID: CGWindowID, in axApp: AXUIElement, pid: pid_t? = nil) -> AXUIElement? {
        AXWindowResolver.element(for: windowID, in: axApp, pid: pid)
    }

    fileprivate static func axElementForMinimizeRestore(windowID: CGWindowID,
                                                        in axApp: AXUIElement) -> AXUIElement? {
        axElement(windowID: windowID,
                  in: axApp)
    }

    fileprivate static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    fileprivate static func boolAttribute(_ element: AXUIElement, _ attribute: String, default defaultValue: Bool) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value
        else { return defaultValue }
        return (value as? Bool) ?? defaultValue
    }

    private static func minimizedState(of axWindow: AXUIElement) -> Bool? {
        SwitcherActivationTargetWindow.minimizedState(of: axWindow)
    }
}

/// Waits for an explicit close to become possible, then observes its result.
/// A delivered request is never repeated. A remaining off-Space or hidden
/// window is revealed so the user can answer its save dialog.
/// Created, polled and finished on the main thread, where its observer is
/// delivered too, so it is `@unchecked Sendable`.
fileprivate final class SwitcherPendingWindowClose: @unchecked Sendable {
    private static let pollInterval: TimeInterval = 0.1
    private static let timeout: TimeInterval = 4.0
    private static let closeResultGrace: TimeInterval = 0.7

    private let item: SwitcherItem
    private let restoresHiddenApp: Bool
    fileprivate let usesSpaceHop: Bool
    private let leavesFullscreen: Bool
    private let observesCloseResult: Bool
    private let completion: (Bool) -> Void
    private let deadline: DispatchTime
    private var closeWasRequested: Bool
    private var closeResultDeadline: DispatchTime?
    private var windowWasClosed = false
    private var generation: UInt64
    private let foregroundPID: pid_t?
    private let foregroundWindowID: CGWindowID?
    private var focusWasSuperseded = false
    private var completed = false
    private var revealGeneration: UInt64?
    private var activationObserver: NSObjectProtocol?
    private var observedExpectedActivation: Bool
    private var appWasReactivated = false

    init(item: SwitcherItem,
         restoresHiddenApp: Bool,
         usesSpaceHop: Bool,
         leavesFullscreen: Bool = false,
         observesCloseResult: Bool,
         closeWasRequested: Bool = false,
         generation: UInt64,
         foregroundPID: pid_t?,
         foregroundWindowID: CGWindowID?,
         completion: @escaping (Bool) -> Void) {
        self.item = item
        self.restoresHiddenApp = restoresHiddenApp
        self.usesSpaceHop = usesSpaceHop
        self.leavesFullscreen = leavesFullscreen
        self.observesCloseResult = observesCloseResult
        self.closeWasRequested = closeWasRequested
        self.closeResultDeadline = closeWasRequested ? .now() + Self.closeResultGrace : nil
        self.generation = generation
        self.foregroundPID = foregroundPID
        self.foregroundWindowID = foregroundWindowID
        self.completion = completion
        self.deadline = .now() + Self.timeout
        self.observedExpectedActivation = !usesSpaceHop
    }

    func start() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            if pid != self.foregroundPID, pid != self.item.pid,
               pid != ProcessInfo.processInfo.processIdentifier {
                self.focusWasSuperseded = true
            }
            guard pid == self.item.pid else { return }
            if self.observedExpectedActivation {
                self.appWasReactivated = true
            } else {
                self.observedExpectedActivation = true
            }
        }
        if usesSpaceHop {
            WindowActivator.activate(item, retry: false)
            generation = WindowActivator.currentActivationGeneration()
        } else if restoresHiddenApp {
            NSRunningApplication(processIdentifier: item.pid)?.unhide()
        }
        revealGeneration = WindowActivator.activationGeneration(for: item.pid)
        poll()
    }

    func cancel() {
        WindowActivator.finishPendingWindowClose(self, success: false)
    }

    func finish(success: Bool) {
        guard !completed else { return }
        completed = true
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if restoresHiddenApp, !closeWasRequested || windowWasClosed,
           let revealGeneration,
           SwitcherSupport.shouldRestoreHiddenApp(
               revealGeneration: revealGeneration,
               currentGeneration: WindowActivator.activationGeneration(for: item.pid),
               appWasReactivated: appWasReactivated
           ),
           let app = NSRunningApplication(processIdentifier: item.pid),
           !app.isTerminated,
           usesSpaceHop || !app.isActive {
            app.hide()
        }
        completion(success)
    }

    private func poll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in
            guard let self, !self.completed, let windowID = self.item.windowID else { return }
            if self.closeWasRequested {
                if WindowActivator.windowExistsForClose(windowID: windowID, ownerPID: self.item.windowOwnerPID) == false {
                    self.windowWasClosed = true
                    WindowActivator.finishPendingWindowClose(self, success: true)
                } else if let deadline = self.closeResultDeadline, DispatchTime.now() < deadline {
                    self.poll()
                } else {
                    let canReveal = self.canRevealRemainingWindow()
                    let finished = WindowActivator.finishPendingWindowClose(self, success: true)
                    // Finish first: cancelling the old hop must not cancel the
                    // new hop, and completion may supersede this request.
                    if canReveal, finished, self.canRevealRemainingWindow() {
                        WindowActivator.activate(self.item, retry: false)
                    }
                }
                return
            }
            guard DispatchTime.now() < self.deadline else {
                WindowActivator.finishPendingWindowClose(self, success: false)
                return
            }
            // A window leaving fullscreen closes wherever it lands, once its
            // close button is enabled again.
            if self.leavesFullscreen || !SpaceWindowBridge.isParkedOnHiddenSpace(windowID),
               WindowActivator.closeWindow(windowID: windowID,
                                           appPID: self.item.pid,
                                           windowOwnerPID: self.item.windowOwnerPID) {
                self.closeWasRequested = true
                if self.observesCloseResult {
                    self.closeResultDeadline = .now() + Self.closeResultGrace
                    self.poll()
                } else {
                    WindowActivator.finishPendingWindowClose(self, success: true)
                }
            } else {
                self.poll()
            }
        }
    }

    private func canRevealRemainingWindow() -> Bool {
        guard !focusWasSuperseded, !appWasReactivated, WindowActivator.isCurrentActivation(generation),
              let foregroundPID, let foregroundWindowID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == foregroundPID else { return false }
        // Native selection of another window in the same app does not change
        // our activation generation or send an app activation notification.
        return WindowActivator.focusedWindowID(for: foregroundPID) == foregroundWindowID
    }
}

/// Made and read by the activation passes, all on the main thread, where its
/// workspace observer is delivered too, so it is `@unchecked Sendable`.
private final class SwitcherAppActivationRetryState: @unchecked Sendable {
    private let targetPID: pid_t
    private var workspaceObserver: Any?
    private(set) var targetWasObservedFrontmost: Bool
    private(set) var isActive = true

    init(targetPID: pid_t) {
        self.targetPID = targetPID
        targetWasObservedFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.observe(frontmostPID: app.processIdentifier)
        }
    }

    func observe(frontmostPID: pid_t?) {
        if frontmostPID == targetPID {
            targetWasObservedFrontmost = true
        }
    }

    func invalidate() {
        guard isActive else { return }
        isActive = false
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
        workspaceObserver = nil
    }

    deinit {
        invalidate()
    }
}

/// Lives on the main thread: its Accessibility observer's source is on the main
/// run loop and its other callbacks arrive on the main queue, so it is
/// `@unchecked Sendable`.
fileprivate final class SwitcherWindowMinimizeRestore: @unchecked Sendable {
    let windowID: CGWindowID
    let targetPID: pid_t
    let targetWindowOwnerPID: pid_t
    let sourcePID: pid_t
    let sourceWindowID: CGWindowID?
    let sourceWindowOwnerPID: pid_t?

    private var observer: AXObserver?
    private var workspaceObserver: Any?
    private let lifecycleLock = NSLock()
    private var active = true
    fileprivate var minimizeIntentObserved = false
    private var minimizeCompletionRestoreScheduled = false
    private let targetBundleIdentifier: String?
    fileprivate let generation: UInt64
    private let sourceBundleIdentifier: String?

    init?(windowID: CGWindowID,
          targetPID: pid_t,
          targetWindowOwnerPID: pid_t,
          sourcePID: pid_t,
          sourceWindowID: CGWindowID?,
          sourceWindowOwnerPID: pid_t?,
          generation: UInt64,
          axWindow: AXUIElement? = nil) {
        guard Permissions.accessibilityGranted else {
            return nil
        }

        let axApp = AXUIElementCreateApplication(targetWindowOwnerPID)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        // The element of this activation's target window is used when the
        // activation already resolved it; the lookup below stays the
        // fallback for the steps that run on their own.
        let windowElement: AXUIElement
        if let provided = axWindow {
            windowElement = provided
        } else {
            guard let resolved = WindowActivator.axElementForMinimizeRestore(windowID: windowID,
                                                                            in: axApp) else {
                return nil
            }
            windowElement = resolved
        }

        var observerRef: AXObserver?
        let observerCreateResult = AXObserverCreate(targetWindowOwnerPID,
                                                    switcherWindowMinimizeRestoreCallback,
                                                    &observerRef)
        guard observerCreateResult == .success,
              let observer = observerRef else {
            return nil
        }

        self.windowID = windowID
        self.targetPID = targetPID
        self.targetWindowOwnerPID = targetWindowOwnerPID
        self.sourcePID = sourcePID
        self.sourceWindowID = sourceWindowID
        self.sourceWindowOwnerPID = sourceWindowOwnerPID
        self.generation = generation
        self.observer = observer
        self.targetBundleIdentifier = NSRunningApplication(processIdentifier: targetPID)?.bundleIdentifier
        self.sourceBundleIdentifier = NSRunningApplication(processIdentifier: sourcePID)?.bundleIdentifier

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let miniaturizedAddResult = AXObserverAddNotification(observer,
                                                              windowElement,
                                                              kAXWindowMiniaturizedNotification as CFString,
                                                              refcon)
        guard miniaturizedAddResult == .success else {
            self.observer = nil
            return nil
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        let focusedAddResult = AXObserverAddNotification(observer,
                                                         axApp,
                                                         kAXFocusedWindowChangedNotification as CFString,
                                                         refcon)
        _ = focusedAddResult
        let mainAddResult = AXObserverAddNotification(observer,
                                                      axApp,
                                                      kAXMainWindowChangedNotification as CFString,
                                                      refcon)
        _ = mainAddResult
        let minimizeButton = WindowActivator.elementAttribute(windowElement,
                                                              kAXMinimizeButtonAttribute as String)
        if let minimizeButton {
            let minimizeButtonAddResult = AXObserverAddNotification(observer,
                                                                    minimizeButton,
                                                                    switcherAXPressedNotification as CFString,
                                                                    refcon)
            _ = minimizeButtonAddResult
        }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppActivation(notification)
        }
    }

    func invalidate() {
        let shouldScheduleTeardown = lifecycleLock.withLock {
            guard active else { return false }
            active = false
            return true
        }
        guard shouldScheduleTeardown else { return }

        // AX callbacks belong to the main runloop. Detach the source on that
        // runloop first, then release the observer in the same turn while this
        // block still owns self. The callback refcon is unretained. Full
        // destruction does not send AXObserverRemoveNotification: the target
        // process drops the client when the observer port dies. A later path
        // that keeps the observer and drops only some notifications must still
        // remove those notifications; this activation has no such path.
        DispatchQueue.main.async { [self] in
            if let workspaceObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            }
            workspaceObserver = nil

            guard let source = self.observer.map(AXObserverGetRunLoopSource) else {
                return
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            withExtendedLifetime(self) {
                self.observer = nil
            }
        }
    }

    private var isActive: Bool {
        lifecycleLock.withLock { active }
    }

    func handle(notification: String) {
        guard isActive else { return }
        if notification == (kAXWindowMiniaturizedNotification as String) {
            minimizeIntentObserved = true
            scheduleMinimizeCompletionRestore()
        } else if notification == switcherAXPressedNotification {
            minimizeIntentObserved = true
            scheduleMinimizeIntentRestore()
        } else if notification == (kAXFocusedWindowChangedNotification as String)
                    || notification == (kAXMainWindowChangedNotification as String) {
            guard minimizeIntentObserved else { return }
            WindowActivator.restoreSourceAfterTargetMinimizeIntent(self)
        }
    }

    private func scheduleMinimizeIntentRestore() {
        scheduleRestorePulses(delays: [0.0, 0.01, 0.03, 0.06, 0.1, 0.16]
                              + denseRestoreDelays(from: 0.24, through: 1.0, step: 0.04),
                              completionDelay: 1.12)
    }

    private func scheduleMinimizeCompletionRestore() {
        guard !minimizeCompletionRestoreScheduled else { return }
        minimizeCompletionRestoreScheduled = true
        scheduleRestorePulses(delays: denseRestoreDelays(from: 0.0, through: 0.45, step: 0.003),
                              completionDelay: 0.5)
    }

    private func scheduleRestorePulses(delays: [TimeInterval], completionDelay: TimeInterval) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.minimizeIntentObserved else { return }
                WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                                       keepPending: true,
                                                                       allowSystemPromotion: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay) { [weak self] in
            guard let self, self.minimizeIntentObserved else { return }
            WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                                   allowSystemPromotion: true)
            WindowActivator.cancelPendingMinimizeRestore(self)
        }
    }

    private func denseRestoreDelays(from start: TimeInterval,
                                    through end: TimeInterval,
                                    step: TimeInterval) -> [TimeInterval] {
        guard step > 0, end >= start else { return [] }
        var delays: [TimeInterval] = []
        var delay = start
        while delay <= end + 0.0001 {
            delays.append(delay)
            delay += step
        }
        return delays
    }

    fileprivate func matchesTargetBundle(_ pid: pid_t?) -> Bool {
        guard let pid,
              pid != targetPID,
              pid != sourcePID,
              let targetBundleIdentifier,
              targetBundleIdentifier != sourceBundleIdentifier else { return false }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == targetBundleIdentifier
    }

    fileprivate func matchesTargetBundle(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != targetPID,
              app.processIdentifier != sourcePID,
              let targetBundleIdentifier,
              targetBundleIdentifier != sourceBundleIdentifier else { return false }
        return app.bundleIdentifier == targetBundleIdentifier
    }

    fileprivate func restoreAfterTargetBundleActivation() {
        guard minimizeIntentObserved else { return }
        WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                               keepPending: true,
                                                               allowSystemPromotion: true)
    }

    private func handleAppActivation(_ notification: Notification) {
        guard isActive,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        if minimizeIntentObserved {
            WindowActivator.restoreSourceAfterTargetMinimizeIntent(self,
                                                                   keepPending: true,
                                                                   allowSystemPromotion: true)
            return
        }
        let activatedMatchesTargetBundle = app.processIdentifier == targetWindowOwnerPID
            || matchesTargetBundle(app)
        guard !SwitcherSupport.shouldKeepMinimizeRestoreObserver(targetPID: targetPID,
                                                                 sourcePID: sourcePID,
                                                                 activatedPID: app.processIdentifier,
                                                                 activatedMatchesTargetBundle: activatedMatchesTargetBundle) else {
            if activatedMatchesTargetBundle {
                restoreAfterTargetBundleActivation()
            }
            return
        }
        WindowActivator.cancelPendingMinimizeRestore()
    }

}

private func switcherWindowMinimizeRestoreCallback(_ observer: AXObserver,
                                                   _ element: AXUIElement,
                                                   _ notification: CFString,
                                                   _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let restore = Unmanaged<SwitcherWindowMinimizeRestore>.fromOpaque(refcon).takeUnretainedValue()
    restore.handle(notification: notification as String)
}

/// The running-app calls activation makes. `NSRunningApplication` is the real
/// one; tests pass apps that log instead of activating.
package protocol SwitcherActivatableApp: AnyObject {
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    var isHidden: Bool { get }
    @discardableResult func unhide() -> Bool
    /// Activation the current app hands over, as macOS 14 asks.
    @discardableResult func activateFromCurrent(options: NSApplication.ActivationOptions) -> Bool
    @discardableResult func activate(options: NSApplication.ActivationOptions) -> Bool
}

extension NSRunningApplication: SwitcherActivatableApp {
    package func activateFromCurrent(options: NSApplication.ActivationOptions) -> Bool {
        activate(from: NSRunningApplication.current, options: options)
    }
}
