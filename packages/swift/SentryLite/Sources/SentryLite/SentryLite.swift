// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

public final class SentryLite: @unchecked Sendable {
    public static let shared = SentryLite()

    private let lock = NSLock()
    private var dsn: SentryDSN?
    private var release: String?
    private var environment: String?
    private var defaultTags: [String: String] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    public static func start(
        dsn: String,
        release: String? = nil,
        environment: String? = nil,
        tags: [String: String] = [:]
    ) {
        shared.configure(dsn: dsn, release: release, environment: environment, tags: tags)
    }

    public func configure(
        dsn: String,
        release: String? = nil,
        environment: String? = nil,
        tags: [String: String] = [:]
    ) {
        let resolvedDsnString = ProcessInfo.processInfo.environment["SENTRY_DSN"] ?? dsn
        guard !resolvedDsnString.isEmpty, let parsed = SentryDSN(string: resolvedDsnString) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        self.dsn = parsed
        self.release = release ?? ProcessInfo.processInfo.environment["SENTRY_RELEASE"]
        self.environment = environment ?? ProcessInfo.processInfo.environment["SENTRY_ENVIRONMENT"] ?? "production"
        self.defaultTags = tags

        installExceptionHandler()
    }

    public static func capture(
        message: String,
        level: SentryLevel = .info,
        tags: [String: String] = [:],
        extra: [String: String] = [:]
    ) {
        shared.capture(message: message, level: level, tags: tags, extra: extra)
    }

    public static func capture(
        error: Error,
        tags: [String: String] = [:],
        extra: [String: String] = [:]
    ) {
        shared.capture(error: error, tags: tags, extra: extra)
    }

    public func capture(
        message: String,
        level: SentryLevel = .info,
        tags: [String: String] = [:],
        extra: [String: String] = [:]
    ) {
        let mergedTags = self.mergedTags(tags)
        let event = SentryEvent(
            level: level,
            message: message,
            release: release,
            environment: environment,
            tags: mergedTags,
            extra: extra.isEmpty ? nil : extra
        )
        send(event: event)
    }

    public func capture(
        error: Error,
        tags: [String: String] = [:],
        extra: [String: String] = [:]
    ) {
        let mergedTags = self.mergedTags(tags)
        let event = SentryEvent(
            level: .error,
            error: error,
            release: release,
            environment: environment,
            tags: mergedTags,
            extra: extra.isEmpty ? nil : extra
        )
        send(event: event)
    }

    private func mergedTags(_ tags: [String: String]) -> [String: String]? {
        lock.lock()
        defer { lock.unlock() }
        var result = defaultTags
        for (k, v) in tags {
            result[k] = v
        }
        return result.isEmpty ? nil : result
    }

    private func send(event: SentryEvent) {
        lock.lock()
        guard let dsn = self.dsn else {
            lock.unlock()
            return
        }
        lock.unlock()

        guard let bodyData = try? JSONEncoder().encode(event) else {
            return
        }

        var request = URLRequest(url: dsn.storeEndpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(dsn.authHeader, forHTTPHeaderField: "X-Sentry-Auth")
        request.httpBody = bodyData

        let task = session.dataTask(with: request)
        task.resume()
    }

    private func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            SentryLite.shared.handleUncaughtException(exception)
        }
    }

    private func handleUncaughtException(_ exception: NSException) {
        lock.lock()
        guard let dsn = self.dsn else {
            lock.unlock()
            return
        }
        let rel = self.release
        let env = self.environment
        let tags = self.defaultTags
        lock.unlock()

        let event = SentryEvent(
            level: .fatal,
            message: "Uncaught NSException: \(exception.name.rawValue) - \(exception.reason ?? "")",
            release: rel,
            environment: env,
            tags: tags.isEmpty ? nil : tags,
            extra: [
                "exception_name": exception.name.rawValue,
                "reason": exception.reason ?? "",
                "call_stack_symbols": exception.callStackSymbols.joined(separator: "\n")
            ]
        )

        guard let bodyData = try? JSONEncoder().encode(event) else { return }

        var request = URLRequest(url: dsn.storeEndpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(dsn.authHeader, forHTTPHeaderField: "X-Sentry-Auth")
        request.httpBody = bodyData

        let sem = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, _, _ in
            sem.signal()
        }
        task.resume()
        _ = sem.wait(timeout: .now() + 2.0)
    }

    public static func flush(timeout: TimeInterval = 2.0) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: min(timeout, 0.5)))
    }
}
