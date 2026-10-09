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
import NexusAgentCore

/// What the shared engine asks this app, answered from the settings the app
/// already saves, so nothing moves for an existing user.
@MainActor
final class StandaloneHost: NexusAgentHost {
    /// This app has no setting for the bot folder: it is always the standard one.
    var configuredBotDirectory: String { "" }

    var startsBotAtLaunch: Bool { UserDefaults.standard.bool(forKey: "autoStart") }

    /// The same key the chat window keeps plan mode under.
    var planMode: Bool {
        get { UserDefaults.standard.bool(forKey: "planMode") }
        set { UserDefaults.standard.set(newValue, forKey: "planMode") }
    }

    var hiddenClaudeSessionIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: "hiddenClaudeSessionIds") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "hiddenClaudeSessionIds") }
    }

    var strings: NexusAgentHostStrings { NexusAgentHostStrings() }

    // The chat window does not run on the engine yet and posts its own
    // notifications, so the engine's turns have nobody to tell. Step 3 of the
    // shared-library design moves the chat onto the engine and fills these in.
    func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {}

    func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {}
}
