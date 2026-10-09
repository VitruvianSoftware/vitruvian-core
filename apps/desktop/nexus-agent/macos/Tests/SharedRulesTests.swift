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

import NexusAgentCore

/// The rules the standalone app took over from its own copies, at the points
/// where the shared rule reads an input differently than the old copy did.
final class SharedRulesTests: XCTestCase {
    func testEnvLinesReadAsTheBotReadsThem() {
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: #"TELEGRAM_BOT_TOKEN="1:abc""#)?.value, "1:abc")
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: "export AGY_MODEL=m1")?.key, "AGY_MODEL")
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: "AGY_MODEL=m1 # the fast one")?.value, "m1")
        XCTAssertNil(NexusAgentEnvFile.assignment(in: "# AGY_MODEL=m1"))
        XCTAssertNil(NexusAgentEnvFile.assignment(in: "no equals sign"))
    }

    /// The standalone skips an empty value so the field keeps its default.
    func testAnEmptyValueIsReportedAsEmpty() {
        XCTAssertEqual(NexusAgentEnvFile.assignment(in: "AGY_MODEL=")?.value, "")
    }

    func testAgyBinMustBeExecutable() {
        let found = NexusAgentSupport.locateAgent(
            environment: ["AGY_BIN": "/nowhere/agy"], home: "/Users/x",
            isExecutable: { $0 == "/opt/homebrew/bin/agy" })
        XCTAssertEqual(found, "/opt/homebrew/bin/agy")
        XCTAssertNil(NexusAgentSupport.locateAgent(environment: [:], home: "/Users/x", isExecutable: { _ in false }))
    }

    func testAModelRowWithABlankNameShowsItsID() {
        let models = NexusAgentSupport.parseModels("Fetching models…\nm1\tFast\nm2\t \n\n")
        XCTAssertEqual(models.map(\.id), ["m1", "m2"])
        XCTAssertEqual(models.map(\.name), ["Fast", "m2"])
    }
}
