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

/// Frames the host sends.
public enum Requests {
    /// The vendor's "EncryptionData": 4 nonce bytes + 4 zeros, `len = 8`.
    /// The device must see this before it answers flash commands.
    public static func handshake(nonce: [UInt8]) -> Frame {
        precondition(nonce.count == 4, "the handshake nonce is 4 bytes")
        return Frame(command: .encryptionHandshake, length: 8, data: nonce + [0, 0, 0, 0])
    }

    /// Ask for the 10 bytes at the lighting address.
    public static func readLighting() -> Frame {
        Frame(command: .readFlash, address: FlashAddress.lighting, length: 10)
    }

    /// Replace the lighting record.
    public static func writeLighting(_ config: LightingConfig) -> Frame {
        Frame(command: .writeFlash, address: FlashAddress.lighting,
              length: UInt8(LightingConfig.recordLength), data: config.encodeRecord())
    }
}

/// Replies the device sends.
///
/// The one trap: hidapi hands back the report ID at `[0]`
/// (`[8, cmd, 0, addrHi, addrLo, len, mode, …]`), while an IOKit
/// input-report callback buffer may not include it (`[cmd, 0, …]`). Every
/// parser takes `includesReportID` and the transport declares its shape.
public enum Responses {
    /// Parses the reply to `Requests.readLighting()`. Checks the frame
    /// checksum, the echoed command and address, and the record checksum.
    public static func parseReadLighting(_ report: [UInt8], includesReportID: Bool) throws -> LightingConfig {
        let payload = try payloadOf(report, includesReportID: includesReportID)
        guard payload[0] == Command.readFlash.rawValue else {
            throw CompXError.malformedResponse("expected a read-flash echo (8), got command \(payload[0])")
        }
        let address = UInt16(payload[2]) << 8 | UInt16(payload[3])
        guard address == FlashAddress.lighting else {
            throw CompXError.malformedResponse("reply is for flash address 0x\(String(address, radix: 16))")
        }
        guard Checksum.isValid(reportID: CompXDevice.reportID, payload: payload) else {
            throw CompXError.badCRC
        }
        return try LightingConfig.decode(record: payload[5..<(5 + LightingConfig.recordLength)])
    }

    /// Whether a reply acknowledges a write: it echoes command 7.
    public static func isWriteAck(_ report: [UInt8], includesReportID: Bool) -> Bool {
        let offset = includesReportID ? 1 : 0
        guard report.count > offset else { return false }
        if includesReportID, report[0] != CompXDevice.reportID { return false }
        return report[offset] == Command.writeFlash.rawValue
    }

    /// The 16 payload bytes of a reply, whichever shape it arrived in.
    public static func payloadOf(_ report: [UInt8], includesReportID: Bool) throws -> [UInt8] {
        let offset = includesReportID ? 1 : 0
        guard report.count >= offset + CompXDevice.payloadLength else {
            throw CompXError.malformedResponse(
                "reply is \(report.count) bytes, need \(offset + CompXDevice.payloadLength)")
        }
        if includesReportID, report[0] != CompXDevice.reportID {
            throw CompXError.malformedResponse("reply has report ID \(report[0]), expected \(CompXDevice.reportID)")
        }
        return Array(report[offset..<(offset + CompXDevice.payloadLength)])
    }
}
