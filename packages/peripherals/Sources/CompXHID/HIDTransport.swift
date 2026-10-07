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

import CompXProtocol

/// The byte pipe to the mouse. `IOKitHIDTransport` is the real one; tests
/// use a scripted mock. A Linux or Windows transport would plug in here.
public protocol HIDTransport: AnyObject {
    /// Sends one output report. `payload` is the 16 bytes AFTER the report ID.
    func write(reportID: UInt8, payload: [UInt8]) throws
    /// Returns the next input report, or throws `CompXError.timeout`.
    func read(timeout: Duration) throws -> [UInt8]
    /// Whether `read` returns the report-ID byte at index 0 (hidapi does).
    var reportsIncludeReportID: Bool { get }
    func close()
}

/// Wraps a transport and logs every frame as hex: `--trace` on the CLI.
/// The quickest way to compare what this package sends with the prototype.
public final class TracingTransport: HIDTransport {
    private let inner: HIDTransport
    private let log: (String) -> Void

    public init(wrapping inner: HIDTransport, log: @escaping (String) -> Void) {
        self.inner = inner
        self.log = log
    }

    public var reportsIncludeReportID: Bool { inner.reportsIncludeReportID }

    public func write(reportID: UInt8, payload: [UInt8]) throws {
        log("-> id=\(reportID) \(hex(payload))")
        try inner.write(reportID: reportID, payload: payload)
    }

    public func read(timeout: Duration) throws -> [UInt8] {
        do {
            let report = try inner.read(timeout: timeout)
            log("<- \(reportsIncludeReportID ? "(with id) " : "")\(hex(report))")
            return report
        } catch {
            log("<- \(error)")
            throw error
        }
    }

    public func close() { inner.close() }

    private func hex(_ bytes: [UInt8]) -> String {
        bytes.map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined(separator: " ")
    }
}

extension Duration {
    /// Seconds as a `TimeInterval`, for APIs that predate `Duration`.
    var timeInterval: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
