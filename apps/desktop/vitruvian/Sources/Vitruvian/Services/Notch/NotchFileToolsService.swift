// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin
import VitruvianCore
import VitruvianDesign

package struct NotchMediaSession: Identifiable {
    package let id = UUID()
    package let inputs: [URL]
    package let tool: MediaTool

    // Spelled out because a memberwise initializer never leaves its module.
    package init(inputs: [URL], tool: MediaTool) {
        self.inputs = inputs
        self.tool = tool
    }
}

/// The island media's measured height, which sizes the island to it.
@MainActor
package protocol NotchMediaHeightTracking: AnyObject {
    var mediaContentHeight: CGFloat? { get }
    func updateMediaHeight(id: UUID, height: CGFloat)
}

@MainActor
package final class NotchFileToolsService: ObservableObject, NotchMediaHeightTracking {
    /// The switches the tools follow. The app passes `.system`.
    package struct Environment {
        /// The island shows its files, and the media tools and the shelf are available.
        package var available: @MainActor () -> Bool
        /// The shelf is switched on.
        package var shelfEnabled: @MainActor () -> Bool

        package init(available: @escaping @MainActor () -> Bool, shelfEnabled: @escaping @MainActor () -> Bool) {
            self.available = available
            self.shelfEnabled = shelfEnabled
        }

        @MainActor package static var system: Environment {
            Environment(
                available: {
                    NotchSupport.showsFiles()
                        && AppFeature.mediaTools.isAvailable && AppFeature.shelf.isAvailable
                },
                shelfEnabled: { UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) })
        }
    }

    package static let shared = NotchFileToolsService(environment: .system)
    package let media = MediaService(replacesExistingOutputs: false)
    @Published package private(set) var mediaSession: NotchMediaSession?
    @Published package private(set) var mediaPresented = false
    @Published package private(set) var mediaContentHeight: CGFloat?
    package private(set) var mediaSelection = MediaWorkspaceSelection()
    private var mediaResults: AnyCancellable?
    @Published package private(set) var isRunning = false
    @Published package private(set) var completed = 0
    @Published package private(set) var total = 0
    @Published package private(set) var outputURLs: [URL] = []
    @Published package private(set) var failure: String?
    @Published package private(set) var wasCancelled = false
    private var operation: NotchArchiveOperation?
    private let queue = DispatchQueue(label: "com.vitruviansoftware.vitruvian.notch.archive", qos: .userInitiated)
    private var generation = UUID()
    private let environment: Environment
    /// Drops onto the tools (`NotchMediaDrop`).
    private lazy var drop = NotchMediaDrop(
        offered: { [weak self] in self?.offersMediaDrop == true },
        busy: { [weak self] in self?.isBusy ?? true },
        openMedia: { [weak self] in self?.openMedia($0, inputs: $1) == true })

    package init(environment: Environment) {
        self.environment = environment
    }
    deinit { operation?.cancel(immediately: true) }

    package var offersMediaDrop: Bool {
        environment.available() && environment.shelfEnabled()
    }

    package var canAcceptMediaDrop: Bool {
        drop.accepts
    }

    /// The media tools or an archive are working.
    private var isBusy: Bool {
        if case .running = media.state { return true }
        return isRunning
    }

    package func mediaDropContent(for pasteboard: NSPasteboard) -> (tool: MediaTool, inputs: [URL])? {
        drop.content(for: pasteboard)
    }

    package func openMediaDrop(_ pasteboard: NSPasteboard) -> Bool {
        drop.open(pasteboard)
    }

    package func updateMediaHeight(id: UUID, height: CGFloat) {
        guard mediaSession?.id == id, height.isFinite, height > 0 else { return }
        let measured = ceil(height)
        if mediaContentHeight != measured { mediaContentHeight = measured }
    }

    package func showMedia() {
        guard offersMediaDrop, mediaSession != nil else { return }
        mediaPresented = true
    }

    package func hideMedia() {
        mediaPresented = false
    }

    package func syncWithPreferences() {
        guard environment.available() else {
            stop()
            return
        }
    }

    /// A real stop, including application termination, must not depend on the
    /// saved switches. Killing the owned child now also works when there will
    /// be no future run-loop turn to deliver a delayed cancellation fallback.
    package func stop() {
        if isRunning { wasCancelled = true }
        generation = UUID()
        operation?.cancel(immediately: true)
        operation = nil
        isRunning = false
        mediaResults = nil
        media.cancel(immediately: true)
        mediaSelection.durationLoading.cancel()
        mediaSelection = MediaWorkspaceSelection()
        mediaSession = nil
        mediaPresented = false
        mediaContentHeight = nil
    }

    @discardableResult
    package func openMedia(_ tool: MediaTool, inputs: [URL]) -> Bool {
        guard environment.available(), NotchFileToolsSupport.accepts(inputs, for: tool) else { return false }
        closeMedia()
        mediaSession = NotchMediaSession(inputs: inputs, tool: tool)
        mediaPresented = true
        mediaResults = media.$state.dropFirst().sink { state in
            guard case let .completed(result) = state, AppFeature.shelf.isAvailable else { return }
            _ = ShelfService.shared.addFiles(result.outputURLs)
        }
        return true
    }

    package func closeMedia() {
        mediaResults = nil
        media.reset()
        mediaSelection.durationLoading.cancel()
        mediaSelection = MediaWorkspaceSelection()
        mediaSession = nil
        mediaPresented = false
        mediaContentHeight = nil
    }

    package func cancel() {
        guard isRunning else { return }
        wasCancelled = true
        operation?.cancel()
    }

    package func archive(_ inputs: [URL], destination: URL, directory: Bool) {
        guard !isRunning, AppFeature.notch.isAvailable, environment.available() else { return }
        guard destination.isFileURL, !inputs.isEmpty, inputs.allSatisfy(\.isFileURL) else {
            failure = CocoaError(.fileWriteInvalidFileName).localizedDescription
            return
        }
        let job = NotchArchiveOperation()
        operation = job
        let id = UUID()
        generation = id
        completed = 0
        total = inputs.count
        outputURLs = []
        failure = nil
        wasCancelled = false
        isRunning = true
        queue.async { [weak self] in
            var failure: String?
            let safeDestination = NotchFileToolsSupport.destinationIsOutsideInputs(destination, inputs: inputs)
            if !safeDestination { failure = CocoaError(.fileWriteInvalidFileName).localizedDescription }
            for input in inputs where safeDestination {
                let output = directory
                    ? MediaSupport.uniqueOutputURL(in: destination, baseName: input.lastPathComponent, fileExtension: "zip")
                    : destination
                do {
                    try job.archive(input, to: output)
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == id else { return }
                        self.completed += 1
                        self.outputURLs.append(output)
                        if AppFeature.shelf.isAvailable { _ = ShelfService.shared.addFiles([output]) }
                    }
                } catch is CancellationError { break }
                catch { failure = error.localizedDescription; break }
            }
            let finalFailure = failure
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == id else { return }
                self.failure = finalFailure
                self.operation = nil
                self.isRunning = false
            }
        }
    }
}
