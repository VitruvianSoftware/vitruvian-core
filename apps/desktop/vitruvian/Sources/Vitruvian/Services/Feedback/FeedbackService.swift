// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import VitruvianCore
import VitruvianDesign

package enum FeedbackKind: String, Codable, CaseIterable {
    case bug
    case feature
}

package struct FeedbackDiagnostics: Codable {
    package let appVersion: String
    package let appBuild: String
    package let macOS: String
    package let macModel: String?
    package let language: String
    package let isBeta: Bool
    package let updateChannel: String

    package static func current() -> FeedbackDiagnostics {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let isBeta = AppInfo.isBeta
        let channel = AppInfo.isDeveloperBuild ? "developer" : (isBeta ? "beta" : (UpdateService.shared.includeBetaUpdates ? "beta-opt-in" : "stable"))
        return FeedbackDiagnostics(
            appVersion: AppInfo.version,
            appBuild: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            macOS: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            macModel: modelIdentifier,
            language: L10n.shared.language.rawValue,
            isBeta: isBeta,
            updateChannel: channel
        )
    }

    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()

    // Spelled out because a memberwise initializer never leaves its module.
    package init(appVersion: String, appBuild: String, macOS: String, macModel: String?, language: String, isBeta: Bool, updateChannel: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.macOS = macOS
        self.macModel = macModel
        self.language = language
        self.isBeta = isBeta
        self.updateChannel = updateChannel
    }
}

private struct FeedbackSubmission: Codable {
    let kind: FeedbackKind
    let message: String
    let diagnostics: FeedbackDiagnostics?
}

package enum FeedbackError: Error {
    case unavailable
    case rateLimited
    case rejected
    case invalidResponse
}

@MainActor
package final class FeedbackService {
    package static let shared = FeedbackService()

    /// Feedback went to upstream's backend. Until Vitruvian has its own, it
    /// targets a reserved `.invalid` host (RFC 6761) and fails closed.
    private let endpoint = URL(string: "https://feedback.invalid/v1/feedback")!
    private let session: URLSession
    private let encoder = JSONEncoder()

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    package func submit(kind: FeedbackKind,
                message: String,
                diagnostics: FeedbackDiagnostics?) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf16.count >= 10, trimmed.utf16.count <= 2_000 else {
            throw FeedbackError.rejected
        }

        let body = try encoder.encode(FeedbackSubmission(
            kind: kind,
            message: trimmed,
            diagnostics: diagnostics
        ))
        guard body.count <= 8 * 1_024 else { throw FeedbackError.rejected }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedbackError.unavailable
        }
        guard data.count <= 16 * 1_024, let http = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        switch http.statusCode {
        case 201:
            guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = payload["id"] as? String,
                  id.range(of: "^[A-Za-z0-9_-]{32}$", options: .regularExpression) != nil
            else { throw FeedbackError.invalidResponse }
        case 429:
            throw FeedbackError.rateLimited
        case 500...599:
            throw FeedbackError.unavailable
        default:
            throw FeedbackError.rejected
        }
    }
}
