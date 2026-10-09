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
//
// Shared by the standalone Nexus Agent app and the Nexus Agent feature of the
// Vitruvian desktop app. Written for the shared library.

import Foundation

/// How the standalone app keeps its providers between launches: two lists
/// of JSON, one for the three built-in providers (all three, each with the
/// command the user may have edited) and one for the user's own. The rules
/// are here, apart from the app, so they can be tested; the app supplies
/// the two pieces of data and decides where they are kept.
extension NexusAgentCLIProvider {
    /// The two lists as they are written.
    public struct StoredLists: Equatable, Sendable {
        public var builtIn: [NexusAgentCLIProvider]
        public var custom: [NexusAgentCLIProvider]

        public init(builtIn: [NexusAgentCLIProvider], custom: [NexusAgentCLIProvider]) {
            self.builtIn = builtIn
            self.custom = custom
        }
    }

    /// One stored list as its providers. Nothing stored, or something that
    /// cannot be read, is no providers: the other list is still read.
    public static func stored(_ data: Data?) -> [NexusAgentCLIProvider] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([NexusAgentCLIProvider].self, from: data)) ?? []
    }

    /// What a host hands the engine as its saved providers, from the two
    /// stored lists. Each list is believed only about its own kind, as the
    /// standalone read them: an entry of the user's own in the built-in
    /// list, or one marked built-in in the user's list, is left out.
    /// `available(saved:)` turns the result into the list a user picks from.
    public static func saved(builtIn: Data?, custom: Data?) -> [NexusAgentCLIProvider] {
        stored(builtIn).filter(\.isBuiltIn) + stored(custom).filter { !$0.isBuiltIn }
    }

    /// The two lists to write when `providers` is saved.
    ///
    /// The built-in list always holds all three, in their fixed order and
    /// under today's names, which is what the standalone wrote. Each takes
    /// its command from `providers` if it is there, and otherwise keeps the
    /// one already stored (`previousBuiltIn`): a caller that saves only the
    /// user's own providers must not undo an edit to a built-in one.
    ///
    /// The user's list is every entry not marked built-in, in order.
    public static func storedLists(saving providers: [NexusAgentCLIProvider],
                                   over previousBuiltIn: [NexusAgentCLIProvider]) -> StoredLists {
        // `available` lets the last copy of a built-in win, so the new ones go last.
        let builtIn = available(saved: previousBuiltIn.filter(\.isBuiltIn) + providers.filter(\.isBuiltIn))
            .filter(\.isBuiltIn)
        return StoredLists(builtIn: builtIn, custom: providers.filter { !$0.isBuiltIn })
    }
}

/// What the standalone app does when a turn ends, or stops to ask for
/// approval: whether its "done" sound plays, and the system notification,
/// if one is due. Decided here, apart from the doing, so the decision can
/// be tested; the app posts the title and body exactly as given.
public struct NexusAgentTurnAnnouncement: Equatable, Sendable {
    public var playsSound: Bool
    public var notificationTitle: String?
    public var notificationBody: String?

    public init(playsSound: Bool, notificationTitle: String? = nil, notificationBody: String? = nil) {
        self.playsSound = playsSound
        self.notificationTitle = notificationTitle
        self.notificationBody = notificationBody
    }

    /// A notification's body is cut to this many characters.
    public static let bodyLimit = 200

    /// The standalone's rules, kept from its own chat.
    ///
    /// The sound is for a reply that arrived with nothing wrong, whether or
    /// not the chat is on screen. The notification is only for a user who
    /// cannot see the chat: a failed turn is "Failed" with the start of
    /// what went wrong, in the words of the chat's error bubble
    /// (`failureDetail`; the notice's text if it has none); any other turn
    /// with a reply is "Done" with the reply's first line that is not
    /// blank. A turn that ended with no reply and no failure says nothing.
    ///
    /// Nor does a turn marked failed with neither words for the failure
    /// nor a reply. That is a turn the user stopped before any of it
    /// arrived: the program ended on the stop signal, which reads as a
    /// bad exit, but the user did it themselves and nothing failed.
    public static func finished(_ notice: NexusAgentTurnNotice, isChatVisible: Bool,
                                strings: NexusAgentHostStrings) -> NexusAgentTurnAnnouncement {
        let reply = notice.text
        var announcement = NexusAgentTurnAnnouncement(playsSound: notice.endedCleanly && !reply.isEmpty)
        guard !isChatVisible else { return announcement }
        if notice.failed {
            let detail = notice.failureDetail ?? ""
            let wentWrong = detail.isEmpty ? reply : detail
            guard !wentWrong.isEmpty else { return announcement }
            announcement.notificationTitle = strings.failedTitle(provider: notice.providerName)
            announcement.notificationBody = String(wentWrong.prefix(bodyLimit))
        } else if !reply.isEmpty {
            let firstLine = reply.components(separatedBy: .newlines)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? reply
            announcement.notificationTitle = strings.doneTitle(provider: notice.providerName)
            announcement.notificationBody = String(firstLine.prefix(bodyLimit))
        }
        return announcement
    }

    /// What the standalone does when a turn stops to ask whether it may
    /// use a tool. The chat shows the request with its Allow button, so a
    /// user looking at it is told nothing more. One who cannot see the
    /// chat gets a notification, or the turn would wait unseen for a
    /// click: the provider's name with the host's "approval required"
    /// words (the ones Vitruvian's notch notice uses), and the tool and
    /// what it wants to run, cut like any other body. No sound of the
    /// app's own.
    public static func needsApproval(_ notice: NexusAgentTurnNotice, isChatVisible: Bool,
                                     strings: NexusAgentHostStrings) -> NexusAgentTurnAnnouncement {
        guard !isChatVisible else { return NexusAgentTurnAnnouncement(playsSound: false) }
        return NexusAgentTurnAnnouncement(playsSound: false,
                                          notificationTitle: strings.approvalRequiredTitle(provider: notice.providerName),
                                          notificationBody: String(notice.text.prefix(bodyLimit)))
    }
}
