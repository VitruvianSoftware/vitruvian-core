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

/// A chat app on this Mac that Vitruvian Speaker reads over the same local API:
/// Beeper Desktop, and Courier, which serves the same two endpoints
/// (`GET v1/accounts`, `GET v1/messages/search`) in the same shape on a
/// port and with a token of its own. One `ChatAppClient` reads either.
public enum ChatApp: String, CaseIterable, Codable, Sendable {
    case beeper
    case courier

    /// Its name in sentences and settings: "Beeper", "Courier".
    public var name: String {
        switch self {
        case .beeper: return "Beeper"
        case .courier: return "Courier"
        }
    }

    /// The program that has to be running: "Beeper Desktop", "Courier".
    public var programName: String {
        switch self {
        case .beeper: return "Beeper Desktop"
        case .courier: return "Courier"
        }
    }

    /// Where it serves its API on this Mac. `localhost`, not `127.0.0.1`:
    /// App Transport Security refuses plain HTTP to an address written as
    /// numbers, and allows it to localhost.
    public var defaultBaseURL: URL {
        switch self {
        case .beeper: return URL(string: "http://localhost:23373")!
        case .courier: return URL(string: "http://localhost:23390")!
        }
    }

    /// Names another address, for tests only: every test run points this
    /// at a port on this Mac that nothing listens on (the Bazel targets'
    /// `env`), so a test that forgets its stand-in never reaches the app.
    public var urlVariable: String {
        switch self {
        case .beeper: return "VITRUVIAN_SPEAKER_BEEPER_URL"
        case .courier: return "VITRUVIAN_SPEAKER_COURIER_URL"
        }
    }

    /// Where its token is made, as the error for a refused token says it.
    public var newTokenSteps: String {
        switch self {
        case .beeper: return "Create a new one in Beeper Desktop under Settings › Integrations › Approved connections."
        case .courier: return "Make a new one in Courier under Settings › Integrations › New connection…"
        }
    }

    /// Where its API is switched on, for when nothing answers.
    public var apiSwitchHint: String {
        switch self {
        case .beeper: return "its Desktop API is off (Beeper Settings › Integrations)"
        case .courier: return "its API is off (Courier Settings › Integrations)"
        }
    }

    /// What a message it passes on is filed under in the history.
    public var source: IncomingMessage.Source {
        switch self {
        case .beeper: return .beeper
        case .courier: return .courier
        }
    }
}
