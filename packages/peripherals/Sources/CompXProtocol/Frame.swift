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

/// One configuration frame: the 16-byte payload of report 8.
///
/// Layout: `[cmd, 0, addrHi, addrLo, len, data[0..<10], crc]`, where `crc`
/// makes the report-ID byte plus all 16 payload bytes sum to `0x55` mod 256.
public struct Frame: Equatable, Sendable {
    public static let maxDataLength = 10

    public let command: Command
    public let address: UInt16
    /// The `len` byte. It is what the device expects, which is not always
    /// `data.count`: a read request carries no data but asks for 10 bytes.
    public let length: UInt8
    public let data: [UInt8]

    public init(command: Command, address: UInt16 = 0, length: UInt8, data: [UInt8] = []) {
        precondition(data.count <= Frame.maxDataLength, "a frame carries at most 10 data bytes")
        self.command = command
        self.address = address
        self.length = length
        self.data = data
    }

    /// The 16 payload bytes, checksum included, WITHOUT the report ID.
    public var payload: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: CompXDevice.payloadLength)
        bytes[0] = command.rawValue
        bytes[2] = UInt8(address >> 8)
        bytes[3] = UInt8(address & 0xFF)
        bytes[4] = length
        for (i, byte) in data.enumerated() { bytes[5 + i] = byte }
        bytes[15] = Checksum.outer(reportID: CompXDevice.reportID, payloadPrefix: bytes[0..<15])
        return bytes
    }

    /// The 17 bytes hidapi writes: the report ID first, then the payload.
    public func encode() -> [UInt8] {
        [CompXDevice.reportID] + payload
    }
}

/// The two checksums of the protocol. Both are "make it sum to 0x55".
public enum Checksum {
    /// The frame checksum: `(0x55 - reportID - Σ payload[0..<15]) mod 256`.
    public static func outer<C: Collection>(reportID: UInt8, payloadPrefix: C) -> UInt8 where C.Element == UInt8 {
        CompXDevice.checksumTarget &- reportID &- sum(payloadPrefix)
    }

    /// The lighting record's own checksum: `(0x55 - Σ first 6) mod 256`.
    public static func inner<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        CompXDevice.checksumTarget &- sum(bytes)
    }

    /// Whether a whole report (report ID + 16 payload bytes) sums to 0x55.
    public static func isValid<C: Collection>(reportID: UInt8, payload: C) -> Bool where C.Element == UInt8 {
        reportID &+ sum(payload) == CompXDevice.checksumTarget
    }

    static func sum<C: Collection>(_ bytes: C) -> UInt8 where C.Element == UInt8 {
        bytes.reduce(0, &+)
    }
}
