// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import XCTest

final class GeoURIParserTests: XCTestCase {
    func testParsesGeoURIWithUncertaintyAndParameters() {
        let parsed = GeoCoordinate.parse("geo:37.7749,-122.4194;u=15", fallbackLabel: "Ferry Building")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.latitude ?? 0, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(parsed?.longitude ?? 0, -122.4194, accuracy: 0.0001)
        XCTAssertEqual(parsed?.label, "Ferry Building")
        XCTAssertEqual(
            parsed?.appleMapsURL.absoluteString,
            "https://maps.apple.com/?ll=37.7749,-122.4194&q=Ferry%20Building"
        )
        XCTAssertEqual(
            parsed?.googleMapsURL.absoluteString,
            "https://www.google.com/maps/search/?api=1&query=37.7749,-122.4194"
        )

        // Parses geo URI with altitude and CRS parameters, and ignores a fallback label identical to the URI.
        let unlabeled = GeoCoordinate.parse(
            "geo:51.5074,-0.1278,12.5;crs=wgs84;u=5",
            fallbackLabel: "geo:51.5074,-0.1278,12.5;crs=wgs84;u=5"
        )
        XCTAssertNotNil(unlabeled)
        XCTAssertEqual(unlabeled?.latitude ?? 0, 51.5074, accuracy: 0.0001)
        XCTAssertEqual(unlabeled?.longitude ?? 0, -0.1278, accuracy: 0.0001)
        XCTAssertNil(unlabeled?.label)
        XCTAssertEqual(
            unlabeled?.appleMapsURL.absoluteString,
            "https://maps.apple.com/?ll=51.5074,-0.1278"
        )

        // Rejects out-of-range latitude and longitude and malformed URIs.
        XCTAssertNil(GeoCoordinate.parse("geo:91.0,-122.4194"))
        XCTAssertNil(GeoCoordinate.parse("geo:-95.0,-122.4194"))
        XCTAssertNil(GeoCoordinate.parse("geo:37.7749,181.0"))
        XCTAssertNil(GeoCoordinate.parse("geo:37.7749,-180.5"))
        XCTAssertNil(GeoCoordinate.parse("https://maps.apple.com/?ll=37.7749,-122.4194"))
        XCTAssertNil(GeoCoordinate.parse("geo:not-a-number,-122.4194"))

        // Parses /location <lat>,<lon> [label] slash command.
        let cmdWithLabel = GeoCoordinate.parseLocationCommand("/location 37.7749,-122.4194 Ferry Building")
        XCTAssertEqual(cmdWithLabel, GeoCoordinate(latitude: 37.7749, longitude: -122.4194, label: "Ferry Building"))

        let cmdWithoutLabel = GeoCoordinate.parseLocationCommand("/location 37.7749,-122.4194")
        XCTAssertEqual(cmdWithoutLabel, GeoCoordinate(latitude: 37.7749, longitude: -122.4194, label: nil))

        XCTAssertNil(GeoCoordinate.parseLocationCommand("/location 95.0,-122.4194"))
    }
}
