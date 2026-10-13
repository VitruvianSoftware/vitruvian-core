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

import VitruvianToolCLI

final class VersionTests: XCTestCase {
    func testVersionPrintsTheSDKsVersionAndNothingElse() {
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["--version"], say: { said.append($0) }), 0)
        XCTAssertEqual(said, [VitruvianToolCommand.version])
    }

    func testTheVersionIsThreeWholeNumbers() {
        let parts = VitruvianToolCommand.version.split(separator: ".", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 3, VitruvianToolCommand.version)
        XCTAssertTrue(parts.allSatisfy { UInt($0) != nil }, VitruvianToolCommand.version)
    }

    func testVersionTakesNothingAfterIt() {
        XCTAssertEqual(VitruvianToolCommand.main(["--version", "extra"], say: { _ in }), 2)
    }

    func testTheUsageNamesIt() {
        var said: [String] = []
        XCTAssertEqual(VitruvianToolCommand.main(["help"], say: { said.append($0) }), 0)
        XCTAssertTrue(said.joined(separator: "\n").contains("vitruvian-tool --version"), "\(said)")
    }
}
