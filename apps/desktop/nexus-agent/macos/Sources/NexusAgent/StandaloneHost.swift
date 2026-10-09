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

import AppKit
import Foundation
import NexusAgentCore

/// What the shared engine asks this app, answered from the settings the app
/// already saves, so nothing moves for an existing user.
///
/// It is the one writer of the three provider keys (`builtInProviders_v3`,
/// `customProviders`, `activeProviderId`). Settings reads and saves its
/// providers through this host and the engine, so the chat and Settings
/// cannot overwrite each other's choice.
@MainActor
final class StandaloneHost: NexusAgentHost {
    /// The conversation the chat has open, for a notification's click to
    /// come back to. Set by whoever builds the engine; the host itself
    /// knows no engine.
    var openConversation: (() -> (id: String?, title: String?))?

    /// Whether the chat is on screen, for a turn that stops to ask for
    /// approval: the engine says so when a turn ends, but not then. Set by
    /// whoever builds the engine, to the engine's own answer; until it is
    /// set no window shows the engine's turns, and the answer is no.
    var chatIsVisible: (() -> Bool)?

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

    /// The same key Settings keeps the selected provider under, as the same
    /// text: the id's capitals-and-dashes form.
    var chosenProviderID: UUID? {
        get { UserDefaults.standard.string(forKey: "activeProviderId").flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: "activeProviderId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activeProviderId")
            }
        }
    }

    /// The two lists this app has always kept, joined: the built-in
    /// providers (whose command the user may have edited) and the user's
    /// own. They are JSON under the same keys, with the same four fields,
    /// as every earlier version wrote. What is read from each list and what
    /// is written to each are the shared rules, which are tested: the
    /// built-in list always holds all three, and saving a list that leaves
    /// a built-in out keeps the one already stored.
    var savedProviders: [NexusAgentCLIProvider] {
        get {
            NexusAgentCLIProvider.saved(builtIn: UserDefaults.standard.data(forKey: "builtInProviders_v3"),
                                        custom: UserDefaults.standard.data(forKey: "customProviders"))
        }
        set {
            let lists = NexusAgentCLIProvider.storedLists(
                saving: newValue,
                over: NexusAgentCLIProvider.stored(UserDefaults.standard.data(forKey: "builtInProviders_v3")))
            Self.save(lists.builtIn, forKey: "builtInProviders_v3")
            Self.save(lists.custom, forKey: "customProviders")
        }
    }

    private static func save(_ providers: [NexusAgentCLIProvider], forKey key: String) {
        guard let data = try? JSONEncoder().encode(providers) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// The same keys the chat window keeps its prompt history and worktree
    /// mode under, in the same shape: a list of text, oldest first, and a
    /// yes or no.
    var promptHistory: [String] {
        get { UserDefaults.standard.stringArray(forKey: "promptHistory") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "promptHistory") }
    }

    var worktreeMode: Bool {
        get { UserDefaults.standard.bool(forKey: "worktreeMode") }
        set { UserDefaults.standard.set(newValue, forKey: "worktreeMode") }
    }

    var strings: NexusAgentHostStrings { NexusAgentHostStrings() }

    /// A turn stopped to ask whether it may use a tool. This app's own
    /// chat never asked: it always let agy skip its prompts. The shared
    /// chat honours the approval mode, so a turn out of sight can now sit
    /// waiting for an Allow click nobody sees, and the user is told with a
    /// notification. Whether one is due, and its words, are the shared
    /// rule, which is tested.
    func turnNeedsApproval(_ notice: NexusAgentTurnNotice) {
        post(NexusAgentTurnAnnouncement.needsApproval(notice, isChatVisible: chatIsVisible?() ?? false,
                                                      strings: strings))
    }

    /// What this app's own chat did when a reply ended: the "done" sound
    /// for a good reply, and a notification when the chat is out of sight.
    /// Whether each is due, and the notification's title and body, are the
    /// shared rule, which is tested; the title comes out as this app has
    /// always worded it, the provider's name and "Done" or "Failed".
    func turnFinished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool) {
        post(NexusAgentTurnAnnouncement.finished(notice, isChatVisible: isChatVisible, strings: strings))
    }

    /// Does what the shared rule decided, with its words as given.
    private func post(_ announcement: NexusAgentTurnAnnouncement) {
        if announcement.playsSound { NSSound(named: "Tink")?.play() }
        guard let title = announcement.notificationTitle, let body = announcement.notificationBody else { return }
        let conversation = openConversation?()
        BackgroundNotificationManager.shared.notify(
            title: title, body: body, sessionUUID: conversation?.id, sessionTitle: conversation?.title)
    }
}
