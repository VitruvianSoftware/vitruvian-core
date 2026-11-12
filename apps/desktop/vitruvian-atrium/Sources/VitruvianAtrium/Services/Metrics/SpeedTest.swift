// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation
import VitruvianCore
import VitruvianDesign

/// A user-triggered internet speed test: latency, then download, then upload,
/// using Cloudflare's public speed endpoints (the same backend speed.cloudflare.com
/// uses). Time-boxed so it stays bounded on any connection. No third-party
/// framework; no user data ever leaves the machine (the upload body is zeros).
///
/// All mutable state is touched only on the session's serial delegate queue;
/// published values are pushed to the main thread.
@MainActor
package final class SpeedTest: NSObject, ObservableObject {
    package static let shared = SpeedTest()

    // The delegate queue reads the clock and arms the time box, so both are `@Sendable`.
    package typealias Clock = @Sendable () -> TimeInterval
    package typealias TimeBoxScheduler = @Sendable (OperationQueue, TimeInterval, @escaping @Sendable () -> Void) -> () -> Void

    package enum Phase: Equatable {
        case idle, latency, download, upload, done
        case failed(String)
    }

    @Published package private(set) var phase: Phase = .idle
    @Published package private(set) var latencyMs: Double?
    @Published package private(set) var downloadMbps: Double?
    @Published package private(set) var uploadMbps: Double?

    package var isRunning: Bool {
        switch phase { case .latency, .download, .upload: return true; default: return false }
    }

    private enum Kind { case none, download, upload }

    private let host = "https://speed.cloudflare.com"
    private let sampleSeconds: TimeInterval
    nonisolated private let clock: Clock
    nonisolated private let scheduleTimeBox: TimeBoxScheduler
    // Cloudflare's __down caps the size just under 100 MB (100 MB+ returns ~nothing),
    // so request under that and loop chunks back-to-back until the time box — that
    // keeps a fast link's pipe full for a full measurement window.
    private let downloadBytes = 90_000_000
    private let uploadBytes = 100_000_000

    private let queue = OperationQueue()
    // Touched only on `queue`; `session` is set once, in init.
    nonisolated(unsafe) private var session: URLSession!
    nonisolated(unsafe) private var task: URLSessionTask?
    nonisolated(unsafe) private var kind: Kind = .none           // touched only on `queue`
    nonisolated(unsafe) private var transferred: Int64 = 0       // touched only on `queue`
    nonisolated(unsafe) private var startedAt: TimeInterval = 0
    nonisolated(unsafe) private var finished = false
    nonisolated(unsafe) private var generation = 0
    nonisolated(unsafe) private var cancelTimeBox: (() -> Void)?

    package init(configuration: URLSessionConfiguration = .ephemeral, sampleSeconds: TimeInterval = 5,
         clock: @escaping Clock = { ProcessInfo.processInfo.systemUptime },
         scheduleTimeBox: @escaping TimeBoxScheduler = { queue, delay, action in
             let work = DispatchWorkItem { queue.addOperation(action) }
             DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: work)
             return { work.cancel() }
         }) {
        self.sampleSeconds = sampleSeconds
        self.clock = clock
        self.scheduleTimeBox = scheduleTimeBox
        super.init()
        queue.maxConcurrentOperationCount = 1
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    package func start() {
        guard !isRunning else { return }
        latencyMs = nil; downloadMbps = nil; uploadMbps = nil
        setPhase(.latency)
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.measureLatency(remaining: 5, best: .greatestFiniteMagnitude)
        }
    }

    package func cancel() {
        queue.addOperation { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.cancelTimeBox?(); self.cancelTimeBox = nil
            self.task?.cancel(); self.task = nil
            self.kind = .none
            self.finished = true
            self.setPhase(.idle)   // inside the op, so it orders after any pending transition
        }
    }

    nonisolated private func setPhase(_ phase: Phase) {
        DispatchQueue.main.async { self.phase = phase }
    }

    // MARK: - Latency (completion-handler tasks bypass the byte-counting delegate)

    nonisolated private func measureLatency(remaining: Int, best: Double) {
        guard remaining > 0 else {
            let value = best == .greatestFiniteMagnitude ? nil : best
            DispatchQueue.main.async { self.latencyMs = value }
            startTransfer(.download)
            return
        }
        let url = URL(string: "\(host)/__down?bytes=0")!
        let started = clock()
        let generation = self.generation
        task = session.dataTask(with: url) { [weak self] _, response, error in
            guard let self else { return }
            let rtt = (self.clock() - started) * 1000
            // Continue on the delegate queue so the transfer phase's `kind` is set
            // there too — otherwise the byte-counting delegate could miss it.
            self.queue.addOperation {
                guard self.generation == generation else { return }
                guard error == nil, Self.isSuccessful(response) else {
                    self.fail(error ?? URLError(.badServerResponse))
                    return
                }
                self.measureLatency(remaining: remaining - 1, best: min(best, rtt))
            }
        }
        task?.resume()
    }

    // MARK: - Download / upload (delegate tasks), time-boxed

    nonisolated private func startTransfer(_ transfer: Kind) {
        generation += 1
        kind = transfer
        transferred = 0
        finished = false
        setPhase(transfer == .download ? .download : .upload)
        startedAt = clock()

        let generation = self.generation
        cancelTimeBox?()   // defensive: never leave a previous time box armed
        cancelTimeBox = scheduleTimeBox(queue, sampleSeconds) { [weak self] in
            guard let self, self.generation == generation else { return }
            self.finishTransfer(timedOut: true)
        }
        beginChunk()
    }

    /// Starts one transfer. Download loops these (each capped under Cloudflare's
    /// limit) until the time box; upload is a single body.
    nonisolated private func beginChunk() {
        guard !finished else { return }
        let task: URLSessionTask
        if kind == .download {
            task = session.dataTask(with: URL(string: "\(host)/__down?bytes=\(downloadBytes)")!)
        } else {
            var request = URLRequest(url: URL(string: "\(host)/__up")!)
            request.httpMethod = "POST"
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            task = session.uploadTask(with: request, from: Data(count: uploadBytes))
        }
        self.task = task
        task.resume()
    }

    nonisolated private func finishTransfer(timedOut: Bool) {
        guard !finished else { return }
        finished = true
        cancelTimeBox?(); cancelTimeBox = nil

        let elapsed = clock() - startedAt
        let bytes = transferred
        if timedOut { task?.cancel() }
        task = nil
        let finishedKind = kind
        kind = .none

        let mbps = elapsed > 0 ? max(0, Double(bytes) * 8 / elapsed / 1_000_000) : 0
        DispatchQueue.main.async {
            if finishedKind == .download { self.downloadMbps = mbps } else { self.uploadMbps = mbps }
        }

        if finishedKind == .download {
            startTransfer(.upload)
        } else {
            setPhase(.done)
        }
    }

    nonisolated private static func isSuccessful(_ response: URLResponse?) -> Bool {
        guard let response = response as? HTTPURLResponse else { return false }
        return (200...299).contains(response.statusCode)
    }

    nonisolated private func fail(_ error: Error) {
        generation += 1
        finished = true
        cancelTimeBox?(); cancelTimeBox = nil
        task?.cancel(); task = nil
        kind = .none
        setPhase(.failed(error.localizedDescription))
    }
}

extension SpeedTest: URLSessionDataDelegate {
    nonisolated package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === task, kind != .none, !finished else {
            completionHandler(.cancel)
            return
        }
        guard Self.isSuccessful(response) else {
            fail(URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    nonisolated package func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if dataTask === task, kind == .download { transferred += Int64(data.count) }
    }

    nonisolated package func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        if task === self.task, kind == .upload { transferred = totalBytesSent }
    }

    nonisolated package func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Ignore a stale completion from a task we already moved past (e.g. the
        // download chunk the time box just cancelled, arriving after upload began).
        guard task === self.task, kind != .none else { return }
        if let error = error as NSError?, error.code != NSURLErrorCancelled, transferred == 0 {
            fail(error)
            return
        }
        if kind == .download, !finished {
            beginChunk()   // keep the pipe full until the time box
        } else {
            finishTransfer(timedOut: false)
        }
    }
}
