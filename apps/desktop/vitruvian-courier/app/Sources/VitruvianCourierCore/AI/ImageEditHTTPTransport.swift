// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The transport photo edits use. Unlike `URLSessionHTTPTransport` it
/// - **never follows a redirect**: the request carries the person's API key, and a redirect would send it on to whatever
///   address the answer names. A redirect ends as a plain network error (`URLError.httpTooManyRedirects`);
/// - **reads the answer as a stream and stops at `maxResponseBytes`** (64 MB), rather than buffering whatever arrives.
///   Going over ends as `URLError.dataLengthExceedsMaximum`, as soon as the running count passes the limit or the
///   answer's declared length does.
public struct ImageEditHTTPTransport: HTTPTransport, @unchecked Sendable {
    public static let maxResponseBytes = 64 * 1024 * 1024
    public static let shared = ImageEditHTTPTransport()

    private let configuration: URLSessionConfiguration
    private let maxResponseBytes: Int

    /// `configuration` is only for tests (a stand-in `URLProtocol`); the default is a fresh session with no cookies or cache.
    public init(
        configuration: URLSessionConfiguration = .ephemeral,
        maxResponseBytes: Int = ImageEditHTTPTransport.maxResponseBytes
    ) {
        self.configuration = configuration
        self.maxResponseBytes = maxResponseBytes
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        let download = ImageEditDownload(maxBytes: maxResponseBytes)
        let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.start(session.dataTask(with: request), continuation: continuation)
            }
        } onCancel: {
            download.cancel()
        }
    }
}

/// One request's delegate: counts what arrives, refuses redirects, and answers once.
private final class ImageEditDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxBytes: Int
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var failure: Error?
    private var cancelledEarly = false

    init(maxBytes: Int) {
        self.maxBytes = maxBytes
    }

    func start(_ task: URLSessionDataTask, continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) {
        let alreadyCancelled = lock.withLock { () -> Bool in
            self.task = task
            self.continuation = continuation
            return cancelledEarly
        }
        if alreadyCancelled {
            task.cancel()
        }
        task.resume()
    }

    func cancel() {
        let task = lock.withLock { () -> URLSessionDataTask? in
            cancelledEarly = true
            return self.task
        }
        task?.cancel()
    }

    /// Records the first reason this download must fail, and stops the task.
    private func fail(_ error: URLError.Code, task: URLSessionTask) {
        lock.withLock { if failure == nil { failure = URLError(error) } }
        task.cancel()
    }

    func urlSession(
        _: URLSession, task: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // No new request: nothing (and not the key) goes to the address the answer names.
        fail(.httpTooManyRedirects, task: task)
        completionHandler(nil)
    }

    func urlSession(
        _: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            lock.withLock { self.response = http }
        }
        // The declared length, from the header too: not every response object reports it as `expectedContentLength`.
        let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) } ?? -1
        if max(response.expectedContentLength, header) > Int64(maxBytes) {
            fail(.dataLengthExceedsMaximum, task: dataTask)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let over = lock.withLock { () -> Bool in
            guard failure == nil else { return false }
            data.append(chunk)
            return data.count > maxBytes
        }
        if over { fail(.dataLengthExceedsMaximum, task: dataTask) }
    }

    func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: Error?) {
        let outcome: Result<(Data, HTTPURLResponse), Error> = lock.withLock {
            if let failure { return .failure(failure) }
            if let error { return .failure(error) }
            guard let response else { return .failure(URLError(.badServerResponse)) }
            return .success((data, response))
        }
        let continuation = lock.withLock { () -> CheckedContinuation<(Data, HTTPURLResponse), Error>? in
            defer { self.continuation = nil; data = Data() }
            return self.continuation
        }
        continuation?.resume(with: outcome)
    }
}
