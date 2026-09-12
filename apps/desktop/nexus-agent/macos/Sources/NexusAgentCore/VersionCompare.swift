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

import Foundation

/// Pure semantic-version helpers, factored out of the @MainActor `UpdateChecker`
/// into their own module (NexusAgentCore) so they can be unit-tested without
/// linking the app's `@main` (which duplicates the test binary's main) (#807).
public enum VersionCompare {
    /// Extract a dotted semantic version (e.g. "1.4.0") from a release tag such as
    /// "nexus-agent-v1.4.0" or "v1.4.0". Falls back to stripping a leading "v".
    public static func extractVersion(from tag: String) -> String {
        if let range = tag.range(of: "\\d+\\.\\d+\\.\\d+", options: .regularExpression) {
            return String(tag[range])
        }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// True when `remote` is a strictly newer dotted version than `current`.
    /// Missing trailing components compare as 0 (so "1.2" == "1.2.0").
    public static func isNewerVersion(remote: String, current: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteParts.count, currentParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let c = i < currentParts.count ? currentParts[i] : 0
            if r > c { return true }
            if r < c { return false }
        }
        return false
    }
}
