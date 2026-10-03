// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

package enum ScreenshotShareDuration: Int, CaseIterable, Codable, Identifiable {
    case oneHour = 3_600
    case sixHours = 21_600
    case twentyFourHours = 86_400

    package var id: Int { rawValue }

    package static func saved(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.integer(forKey: DefaultsKey.screenshotUploadDuration)) ?? .oneHour
    }

    package func title(_ strings: ScreenshotFeatureStrings) -> String {
        switch self {
        case .oneHour: strings.shareOneHour
        case .sixHours: strings.shareSixHours
        case .twentyFourHours: strings.shareTwentyFourHours
        }
    }
}

package struct ScreenshotShareRecord: Codable, Equatable, Identifiable {
    package let id: String
    package let endpoint: URL
    package let expiresAt: Date
    package let deleteToken: String

    package var url: URL {
        endpoint.appendingPathComponent("s", isDirectory: true)
            .appendingPathComponent(id, isDirectory: false)
    }

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, endpoint: URL, expiresAt: Date, deleteToken: String) {
        self.id = id
        self.endpoint = endpoint
        self.expiresAt = expiresAt
        self.deleteToken = deleteToken
    }
}

/// Keeps clipboard retries tied to the capture that produced the link.
package struct ScreenshotLinkCopyRetry {
    private var pending: (captureID: UUID, record: ScreenshotShareRecord)?

    package mutating func remember(_ record: ScreenshotShareRecord, for captureID: UUID) {
        pending = (captureID, record)
    }

    package mutating func clear() { pending = nil }

    package func record(for captureID: UUID, availableRecords: [ScreenshotShareRecord],
                now: Date = Date()) -> ScreenshotShareRecord? {
        guard let pending, pending.captureID == captureID,
              pending.record.expiresAt > now,
              availableRecords.contains(pending.record) else { return nil }
        return pending.record
    }

    // Spelled out because a default initializer never leaves its module.
    package init() {}
}

package struct ScreenshotShareResponse: Decodable {
    package let id: String
    package let viewPath: String
    package let expiresAt: String
    package let deleteToken: String

    // Spelled out because a memberwise initializer never leaves its module.
    package init(id: String, viewPath: String, expiresAt: String, deleteToken: String) {
        self.id = id
        self.viewPath = viewPath
        self.expiresAt = expiresAt
        self.deleteToken = deleteToken
    }
}

package enum ScreenshotSharingSupport {
    package static func uploadShortcutEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.screenshotUploadShortcutEnabled)
            && defaults.bool(forKey: DefaultsKey.screenshotSharingEnabled)
    }

    package static func retainsLatestCapture(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.screenshotLastCaptureShortcutEnabled)
            || uploadShortcutEnabled(in: defaults)
    }

    @discardableResult
    package static func copyLink(_ record: ScreenshotShareRecord,
                         using copy: (URL) -> Bool,
                         dismiss: () -> Void) -> Bool {
        guard copy(record.url) else { return false }
        dismiss()
        return true
    }

    /// Temporary links were served by upstream's own backend, which the fork
    /// must not send users' captures to. Until Vitruvian runs its own, uploads
    /// go to a reserved `.invalid` host (RFC 6761) that never resolves, so they
    /// fail closed and nothing leaves the Mac.
    package static let productionEndpoint = URL(string: "https://sharing.invalid")!
    package static let developerBundleIdentifier = "com.vitruviansoftware.vitruvian.dev"
    package static let maximumUploadBytes = 25 * 1_024 * 1_024

    package static func endpoint(bundleIdentifier: String?, developerOverride: String?) -> URL {
        guard bundleIdentifier == developerBundleIdentifier,
              let developerOverride,
              let candidate = sanitizedEndpoint(developerOverride)
        else { return productionEndpoint }
        return candidate
    }

    package static func sanitizedEndpoint(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.isEmpty || components.path == "/"
        else { return nil }
        components.scheme = "https"
        components.path = ""
        return components.url
    }

    package static func uploadURL(endpoint: URL, duration: ScreenshotShareDuration) -> URL? {
        let base = endpoint.appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent("screenshots", isDirectory: false)
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "expiresIn",
                                               value: String(duration.rawValue))]
        return components.url
    }

    package static func record(response: ScreenshotShareResponse,
                       endpoint: URL,
                       now: Date = Date()) -> ScreenshotShareRecord? {
        guard let expiresAt = expirationDate(response.expiresAt) else { return nil }
        guard response.id.range(of: "^[A-Za-z0-9_-]{32}$",
                                options: .regularExpression) != nil,
              response.deleteToken.range(of: "^[A-Za-z0-9_-]{43}$",
                                         options: .regularExpression) != nil,
              response.viewPath == "/s/\(response.id)",
              expiresAt > now,
              expiresAt <= now.addingTimeInterval(24 * 60 * 60 + 5 * 60)
        else { return nil }
        return ScreenshotShareRecord(id: response.id,
                                     endpoint: endpoint,
                                     expiresAt: expiresAt,
                                     deleteToken: response.deleteToken)
    }

    package static func expirationDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
