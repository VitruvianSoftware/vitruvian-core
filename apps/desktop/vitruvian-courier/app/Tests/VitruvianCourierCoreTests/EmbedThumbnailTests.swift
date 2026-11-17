// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import XCTest

@testable import VitruvianCourierCore

final class EmbedThumbnailTests: XCTestCase {
    func testAValidVideoIDMakesYouTubesPictureAddress() {
        XCTAssertEqual(EmbedThumbnail.youTubeURL(videoID: "dQw4w9WgXcQ")?.absoluteString,
                       "https://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")
        XCTAssertNotNil(EmbedThumbnail.youTubeURL(videoID: "a-_B1234567"))
    }

    func testAnIDThatIsNotExactlyElevenSafeCharactersIsRefused() {
        for bad in ["", "short", "dQw4w9WgXcQx", "dQw4w9WgXc!", "dQw4w9Wg/cQ", "dQw4w9Wg?cQ", "dQw4w9WgXc ", "dQw4w9WgXcé",
                    "../../etc/p", "dQw4w9WgXc\n"] {
            XCTAssertNil(EmbedThumbnail.youTubeURL(videoID: bad), "\(bad.debugDescription) must be refused")
        }
    }

    func testOnlyHTTPSAddressesAreFetched() async {
        let image = await EmbedThumbnail.fetch(URL(string: "http://i.ytimg.com/vi/dQw4w9WgXcQ/mqdefault.jpg")!)
        XCTAssertNil(image)
    }
}
