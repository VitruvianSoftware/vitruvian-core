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

import VitruvianToolProtocol

/// The files under `protocol/` and `conformance/`, as the tests read them.
enum ProtocolFiles {
    /// A file of the package, by its path from the package's folder. Bazel
    /// puts it among the test's runfiles; SwiftPM and Xcode find it beside
    /// the sources. A file that cannot be found fails the test.
    static func data(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> Data {
        var candidates: [String] = []
        let environment = ProcessInfo.processInfo.environment
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append("\(runfiles)/\(workspace)/packages/vitruvian-sdk/\(path)")
            }
        }
        // Outside Bazel: this file is three folders below the package.
        var package = URL(fileURLWithPath: "\(file)")
        for _ in 0..<3 { package.deleteLastPathComponent() }
        candidates.append(package.appendingPathComponent(path).path)
        for candidate in candidates {
            if let data = FileManager.default.contents(atPath: candidate) { return data }
        }
        XCTFail("\(path) is missing; looked in \(candidates)", file: file, line: line)
        return Data()
    }

    static func json(_ path: String, file: StaticString = #filePath, line: UInt = #line) -> JSONValue {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data(path, file: file, line: line)) else {
            XCTFail("\(path) is not JSON", file: file, line: line)
            return .null
        }
        return value
    }

    /// The names of the fields a value of a Swift type holds.
    static func fields(of value: Any) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    /// The names of the fields a schema's definition declares.
    static func fields(declaredBy definition: JSONValue?) -> Set<String> {
        Set((definition?["properties"]?.objectValue ?? [:]).keys)
    }
}
