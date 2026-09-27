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

import Darwin
import Foundation

/// What a pairing QR code holds, and where it has to point.
///
/// A web link, not a vitruvian-remote:// one: Pixel's camera shows a custom
/// scheme as plain text (Google issue 321657269) but opens any http link. The
/// agent's `/pair` page turns that link into the app's own with one tap.
public enum QRPairing {
    /// The link to encode. `address` is this Mac's Tailscale IPv4: the one
    /// address both the phone can reach and the agent listens on.
    public static func pageURL(address: String, code: String) -> URL? {
        guard PairCode.normalize(code) == code, isTailscaleIPv4(address) else { return nil }
        return URL(string: "http://\(address):7411/pair?code=\(code)")
    }

    /// A fresh six-digit code from the system's secure generator.
    public static func newCode() -> String {
        var rng = SystemRandomNumberGenerator()
        return String(format: "%06d", Int.random(in: 0..<1_000_000, using: &rng))
    }

    /// True for 100.64.0.0/10, the range Tailscale assigns from. Mirrors
    /// tailscaleIPv4() in the agent, which listens on exactly this address.
    public static func isTailscaleIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (octets[1] & 0xC0) == 64
    }

    /// This Mac's Tailscale IPv4, read from the interfaces directly, the same
    /// way the agent finds it. Nil when Tailscale is not up.
    public static func tailscaleAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let sa = ifa.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let rc = getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard rc == 0 else { continue }
            let text = String(cString: host)
            if isTailscaleIPv4(text) { return text }
        }
        return nil
    }
}
