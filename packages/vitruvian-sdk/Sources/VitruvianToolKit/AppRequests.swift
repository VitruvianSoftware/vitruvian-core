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
@_exported import VitruvianToolProtocol

/// A request a tool makes of the app: what it carries is the value itself,
/// `method` is its name on the link, and `Answer` is what a result holds.
///
/// Every request of the protocol has one type here, and a test holds
/// the list against `ToolMethod`. A tool calls one with `App.send`, or with
/// the method of `App` that wraps it.
public protocol AppRequest: Encodable {
    associatedtype Answer: Decodable
    static var method: ToolMethod { get }
}

/// `notify/beep` carries nothing.
public struct NotifyBeepParams: Codable, Equatable, Sendable {
    public init() {}
}

/// `clipboard/readText` carries nothing.
public struct ClipboardReadTextParams: Codable, Equatable, Sendable {
    public init() {}
}

extension NotifyHUDParams: AppRequest {
    public typealias Answer = EmptyObject
    public static var method: ToolMethod { .notifyHUD }
}

extension NotifyBeepParams: AppRequest {
    public typealias Answer = EmptyObject
    public static var method: ToolMethod { .notifyBeep }
}

extension OpenURLParams: AppRequest {
    public typealias Answer = OpenURLResult
    public static var method: ToolMethod { .openURL }
}

extension ClipboardReadTextParams: AppRequest {
    public typealias Answer = ClipboardReadTextResult
    public static var method: ToolMethod { .clipboardReadText }
}

extension ClipboardWriteTextParams: AppRequest {
    public typealias Answer = ClipboardWriteTextResult
    public static var method: ToolMethod { .clipboardWriteText }
}

extension KeystrokesPasteParams: AppRequest {
    public typealias Answer = EmptyObject
    public static var method: ToolMethod { .keystrokesPaste }
}

extension KeystrokesPressMenuItemParams: AppRequest {
    public typealias Answer = KeystrokesPressMenuItemResult
    public static var method: ToolMethod { .keystrokesPressMenuItem }
}

extension ProcessesTerminateParams: AppRequest {
    public typealias Answer = EmptyObject
    public static var method: ToolMethod { .processesTerminate }
}

extension StorageGetParams: AppRequest {
    public typealias Answer = StorageGetResult
    public static var method: ToolMethod { .storageGet }
}

extension StorageSetParams: AppRequest {
    public typealias Answer = EmptyObject
    public static var method: ToolMethod { .storageSet }
}

extension UIBadgeParams: AppRequest {
    public typealias Answer = EmptyObject
    public static var method: ToolMethod { .uiBadge }
}

/// The requests above, by name, for a test to hold against `ToolMethod`.
public enum AppRequests {
    public static let methods: [ToolMethod] = [
        NotifyHUDParams.method, NotifyBeepParams.method, OpenURLParams.method, ClipboardReadTextParams.method,
        ClipboardWriteTextParams.method, KeystrokesPasteParams.method, KeystrokesPressMenuItemParams.method,
        ProcessesTerminateParams.method, StorageGetParams.method, StorageSetParams.method, UIBadgeParams.method,
    ]
}
