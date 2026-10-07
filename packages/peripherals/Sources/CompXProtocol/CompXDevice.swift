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

/// Identity and wire constants of the CompX mouse chipset used by the
/// GravaStar Mercury (USB `3554:F549`), as reverse-engineered from the
/// vendor's ControlHub WebHID tool.
public enum CompXDevice {
    public static let vendorID: Int = 0x3554
    public static let productID: Int = 0xF549
    /// The vendor-defined top-level collection that answers configuration
    /// commands. On macOS it is the primary usage page of interface 1.
    public static let vendorUsagePage: Int = 0xFF05
    /// Every configuration frame travels as numbered report 8.
    public static let reportID: UInt8 = 8
    /// Bytes after the report ID: `[cmd, 0, addrHi, addrLo, len, data×10, crc]`.
    public static let payloadLength = 16
    /// Everything on the wire is checksummed so that its bytes sum to this.
    public static let checksumTarget: UInt8 = 0x55
}

/// The command byte, `payload[0]`.
public enum Command: UInt8, Sendable {
    /// The vendor's "EncryptionData": a nonce the device expects first.
    case encryptionHandshake = 1
    case writeFlash = 7
    case readFlash = 8
}

/// Addresses in the device's configuration flash.
public enum FlashAddress {
    /// The 7-byte lighting record (the vendor's `Tt.Light`, 160).
    public static let lighting: UInt16 = 0x00A0
}

/// Every failure in this package, from codec to device.
public enum CompXError: Error, Equatable, Sendable, CustomStringConvertible {
    /// A reply was too short, echoed the wrong command, or held an unknown value.
    case malformedResponse(String)
    /// A write was not echoed back as command 7.
    case notAcknowledged
    /// A checksum did not add up.
    case badCRC
    /// A speed/brightness outside 0-9, or a similar input error.
    case valueOutOfRange(String)
    /// No GravaStar mouse is attached (dongle unplugged, laptop undocked).
    case deviceNotFound
    /// The device did not reply in time.
    case timeout
    /// An IOKit call failed with the given `IOReturn` code.
    case io(operation: String, code: Int32)

    public var description: String {
        switch self {
        case let .malformedResponse(why): return "malformed response from mouse: \(why)"
        case .notAcknowledged: return "mouse did not acknowledge the lighting write"
        case .badCRC: return "checksum mismatch in reply from mouse"
        case let .valueOutOfRange(what): return "value out of range: \(what)"
        case .deviceNotFound: return "mouse not found"
        case .timeout: return "timed out waiting for the mouse to reply"
        case let .io(operation, code):
            return "\(operation) failed (IOReturn 0x\(String(UInt32(bitPattern: code), radix: 16)))"
        }
    }
}
