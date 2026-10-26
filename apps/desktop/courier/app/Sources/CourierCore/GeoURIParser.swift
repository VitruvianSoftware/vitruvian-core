// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Parsed geographic coordinate from an RFC 5870 `geo:` URI or `/location` slash command.
public struct GeoCoordinate: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let label: String?

    public init(latitude: Double, longitude: Double, label: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = (trimmed?.isEmpty == false) ? trimmed : nil
    }

    /// Parses an RFC 5870 `geo:<lat>,<lon>[,<alt>][;params][?query]` URI, validating latitude (`-90...90`)
    /// and longitude (`-180...180`).
    public static func parse(_ geoURI: String, fallbackLabel: String? = nil) -> GeoCoordinate? {
        let trimmedURI = geoURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedURI.lowercased().hasPrefix("geo:") else { return nil }
        let afterScheme = String(trimmedURI.dropFirst(4))
        guard !afterScheme.isEmpty else { return nil }

        // Separate query string (?q=...) if present.
        let querySplit = afterScheme.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let beforeQuery = String(querySplit[0])
        var queryLabel: String?
        if querySplit.count > 1 {
            let queryString = String(querySplit[1])
            var comps = URLComponents()
            comps.percentEncodedQuery = queryString
            if let qValue = comps.queryItems?.first(where: { $0.name.lowercased() == "q" })?.value {
                let cleaned = qValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    queryLabel = cleaned
                }
            }
        }

        // Strip RFC 5870 semicolon parameters (;u=15;crs=wgs84).
        let paramSplit = beforeQuery.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        let coordPart = String(paramSplit[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let components = coordPart.split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3 else { return nil }

        let latString = components[0].trimmingCharacters(in: .whitespaces)
        let lonString = components[1].trimmingCharacters(in: .whitespaces)
        guard let lat = Double(latString),
              let lon = Double(lonString),
              lat.isFinite,
              lon.isFinite,
              lat >= -90.0,
              lat <= 90.0,
              lon >= -180.0,
              lon <= 180.0
        else {
            return nil
        }

        var resolvedLabel: String?
        if let fallback = fallbackLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty,
           fallback.caseInsensitiveCompare(trimmedURI) != .orderedSame,
           fallback.caseInsensitiveCompare("Location") != .orderedSame {
            resolvedLabel = fallback
        } else if let queryLabel {
            resolvedLabel = queryLabel
        }

        return GeoCoordinate(latitude: lat, longitude: lon, label: resolvedLabel)
    }

    /// Parses a `/location <lat>,<lon> [label]` composer command.
    public static func parseLocationCommand(_ text: String) -> GeoCoordinate? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("/location") else { return nil }
        let remainder = trimmed.dropFirst("/location".count)
        guard let firstChar = remainder.first, firstChar.isWhitespace else { return nil }
        let args = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let commaIndex = args.firstIndex(of: ",") else { return nil }

        let latPart = args[..<commaIndex].trimmingCharacters(in: .whitespaces)
        let afterComma = args[args.index(after: commaIndex)...].trimmingCharacters(in: .whitespaces)
        guard !latPart.isEmpty, !afterComma.isEmpty else { return nil }

        let lonEndIndex = afterComma.firstIndex(where: { $0.isWhitespace }) ?? afterComma.endIndex
        let lonPart = String(afterComma[..<lonEndIndex])
        let labelPart = afterComma[lonEndIndex...].trimmingCharacters(in: .whitespacesAndNewlines)

        guard let lat = Double(latPart),
              let lon = Double(lonPart),
              lat.isFinite,
              lon.isFinite,
              lat >= -90.0,
              lat <= 90.0,
              lon >= -180.0,
              lon <= 180.0
        else {
            return nil
        }

        return GeoCoordinate(
            latitude: lat,
            longitude: lon,
            label: labelPart.isEmpty ? nil : labelPart
        )
    }

    private var coordinateQueryValue: String {
        "\(Self.trimTrailingZeros(latitude)),\(Self.trimTrailingZeros(longitude))"
    }

    /// Formatted coordinate pair for human display (`37.7749, -122.4194`).
    public var formattedCoordinates: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }

    /// Text placed on the pasteboard when clicking **Copy Location**.
    public var copyText: String {
        if let label, !label.isEmpty {
            return "\(label) (\(formattedCoordinates))"
        }
        return formattedCoordinates
    }

    /// Opens in Apple Maps (`https://maps.apple.com/?ll=<lat>,<lon>&q=<label>`).
    public var appleMapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        var items = [URLQueryItem(name: "ll", value: coordinateQueryValue)]
        if let label, !label.isEmpty {
            items.append(URLQueryItem(name: "q", value: label))
        }
        components.queryItems = items
        return components.url ?? URL(string: "https://maps.apple.com/")!
    }

    /// Opens in Google Maps (`https://www.google.com/maps/search/?api=1&query=<lat>,<lon>`).
    public var googleMapsURL: URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: coordinateQueryValue),
        ]
        return components.url ?? URL(string: "https://www.google.com/maps")!
    }

    private static func trimTrailingZeros(_ value: Double) -> String {
        let raw = String(value)
        if raw.hasSuffix(".0") {
            return String(raw.dropLast(2))
        }
        return raw
    }
}
