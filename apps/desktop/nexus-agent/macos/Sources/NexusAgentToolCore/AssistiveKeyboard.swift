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

import CoreGraphics
import Foundation

/// Whether a click outside the Quick Prompt pressed a key of the macOS
/// Accessibility Keyboard, which must not close the prompt: each key is a
/// click on another process's window. As the Vitruvian app's guard
/// (apps/desktop/vitruvian/Sources/Vitruvian/Services/AssistiveKeyboard.swift),
/// the topmost window under the point decides, a fully transparent one is
/// clicked through, and the tool's own windows never block the answer.
public enum AssistiveKeyboard {
    public static let bundleID = "com.apple.inputmethod.AssistiveControl"
    /// The owner names the keyboard's windows report: the input method's
    /// process calls itself "Panel" on recent systems.
    public static let ownerNames: Set<String> = ["Panel", "AssistiveControl", "com.apple.AssistiveControl"]

    /// `point` in CoreGraphics coordinates (origin top-left); `windows` as
    /// `CGWindowListCopyWindowInfo` lists them, front to back.
    public static func ownsPoint(_ point: CGPoint, windows: [[String: Any]], keyboardPID: pid_t?,
                                 ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Bool {
        for window in windows {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  CGRect(x: x, y: y, width: width, height: height).contains(point)
            else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? CGFloat, alpha <= 0 { continue }
            let owner = window[kCGWindowOwnerPID as String] as? pid_t
            if let keyboardPID, owner == keyboardPID { return true }
            if let name = window[kCGWindowOwnerName as String] as? String, ownerNames.contains(name) { return true }
            if owner == ownPID { continue }
            return false
        }
        return false
    }

    /// `point` in Cocoa coordinates (origin bottom-left, as
    /// `NSEvent.mouseLocation`), flipped against the primary screen's
    /// height, `primaryHeight`.
    public static func ownsCocoaPoint(_ point: CGPoint, primaryHeight: CGFloat, windows: [[String: Any]],
                                      keyboardPID: pid_t?) -> Bool {
        ownsPoint(CGPoint(x: point.x, y: primaryHeight - point.y), windows: windows, keyboardPID: keyboardPID)
    }
}
