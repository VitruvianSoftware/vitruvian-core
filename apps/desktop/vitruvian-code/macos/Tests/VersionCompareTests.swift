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

import XCTest

import VitruvianCodeCore

final class VersionCompareTests: XCTestCase {
    func testExtractVersionFromComponentPrefixedTag() {
        XCTAssertEqual(VersionCompare.extractVersion(from: "vitruvian-code-v1.34.0"), "1.34.0")
    }

    func testExtractVersionFromVPrefixedTag() {
        XCTAssertEqual(VersionCompare.extractVersion(from: "v2.0.0"), "2.0.0")
    }

    func testExtractVersionFromBareVersion() {
        XCTAssertEqual(VersionCompare.extractVersion(from: "1.2.3"), "1.2.3")
    }

    func testTheUpdateAssetIsExactlyTheMacosZip() {
        XCTAssertEqual(VersionCompare.updateAssetName(version: "1.33.0"), "VitruvianCode-1.33.0-macos.zip")
        let names = ["vitruvian-code-tool-1.33.0.zip", "VitruvianCode-1.33.0-macos.dmg", "VitruvianCode-1.33.0-macos.zip.sha256",
                     "VitruvianCode-1.33.0-macos.zip", "VitruvianCode-1.32.0-macos.zip"]
        XCTAssertEqual(VersionCompare.updateAsset(in: names, version: "1.33.0"), "VitruvianCode-1.33.0-macos.zip")
        XCTAssertNil(VersionCompare.updateAsset(in: ["vitruvian-code-tool-1.33.0.zip"], version: "1.33.0"))
        XCTAssertNil(VersionCompare.updateAsset(in: names, version: "1.34.0"))
        XCTAssertFalse(VersionCompare.updateAssetName(version: "1.33.0").contains("universal"))
    }

    func testIsNewerVersionDetectsPatchMinorMajorBumps() {
        XCTAssertTrue(VersionCompare.isNewerVersion(remote: "1.10.2", current: "1.9.0"))
        XCTAssertTrue(VersionCompare.isNewerVersion(remote: "2.0.0", current: "1.99.99"))
        XCTAssertTrue(VersionCompare.isNewerVersion(remote: "1.0.1", current: "1.0.0"))
    }

    func testIsNewerVersionIsFalseForEqualOrOlder() {
        XCTAssertFalse(VersionCompare.isNewerVersion(remote: "1.0.0", current: "1.0.0"))
        XCTAssertFalse(VersionCompare.isNewerVersion(remote: "1.0.0", current: "1.0.1"))
    }

    func testIsNewerVersionTreatsMissingComponentsAsZero() {
        XCTAssertTrue(VersionCompare.isNewerVersion(remote: "1.2.1", current: "1.2"))
        XCTAssertFalse(VersionCompare.isNewerVersion(remote: "1.2", current: "1.2.0"))
    }
}
