// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// A bridge's notice of a call, in Courier's words. The bridge's body is its own English ("Incoming call. Use the
// WhatsApp app to answer.", "Started a video call", "Call ended"), so it is never shown: the engine reads each notice
// as it arrives and writes what happened into the content (`fi.courier.call`, beside an action message of type call),
// and the chat, the chat list and notifications say it from that.

extension CallNote {
    /// Reads a call note from an event's content: an action message (`com.beeper.action_message`) of type call, with
    /// the engine's reading (`fi.courier.call`). One without a reading (stored before the engine read calls) rang,
    /// voice or video as its call_type says. A state or media this app doesn't know reads as ringing, no media. Nil
    /// for anything else. (The engine's twin: parseCallNote.)
    static func of(_ content: JSONValue) -> CallNote? {
        guard let action = content["com.beeper.action_message"], action["type"]?.stringValue == "call" else {
            return nil
        }
        guard let read = content["fi.courier.call"], case .object = read else {
            return CallNote(state: .ringing, media: known(CallMedia(rawValue: action["call_type"]?.stringValue ?? "")))
        }
        let state = CallState(rawValue: read["state"]?.stringValue ?? "")
        return CallNote(state: CallState.known.contains(state) ? state : .ringing,
                        media: known(CallMedia(rawValue: read["media"]?.stringValue ?? "")))
    }

    private static func known(_ media: CallMedia) -> CallMedia {
        CallMedia.known.contains(media) ? media : .unknown
    }

    /// What the call was, as a line: "Missed video call", "Incoming call". `mine`: I made the call, so it rang for
    /// them ("Outgoing call") and they didn't answer ("Call not answered").
    public func words(mine: Bool) -> String {
        switch (state, media) {
        case (.started, .voice): return String(localized: "Voice call started")
        case (.started, .video): return String(localized: "Video call started")
        case (.started, _): return String(localized: "Call started")
        case (.missed, .voice): return mine ? String(localized: "Voice call not answered")
            : String(localized: "Missed voice call")
        case (.missed, .video): return mine ? String(localized: "Video call not answered")
            : String(localized: "Missed video call")
        case (.missed, _): return mine ? String(localized: "Call not answered") : String(localized: "Missed call")
        case (.ended, .voice): return String(localized: "Voice call ended")
        case (.ended, .video): return String(localized: "Video call ended")
        case (.ended, _): return String(localized: "Call ended")
        case (.declined, .voice): return String(localized: "Voice call declined")
        case (.declined, .video): return String(localized: "Video call declined")
        case (.declined, _): return String(localized: "Call declined")
        case (.dropped, .voice): return String(localized: "Voice call dropped")
        case (.dropped, .video): return String(localized: "Video call dropped")
        case (.dropped, _): return String(localized: "Call dropped")
        case (_, .voice): return mine ? String(localized: "Outgoing voice call") : String(localized: "Incoming voice call")
        case (_, .video): return mine ? String(localized: "Outgoing video call") : String(localized: "Incoming video call")
        default: return mine ? String(localized: "Outgoing call") : String(localized: "Incoming call")
        }
    }

    /// Whether the call is news: it rang (or a group's call started), or was missed. That it ended, was declined or
    /// dropped is a record of a call already told: it doesn't count unread or notify. A call I made is never news,
    /// as nothing of mine is. (The engine's twin: isCallRecord.)
    public var isNews: Bool { ![.ended, .declined, .dropped].contains(state) }

    /// Whether an event is news as far as calls go: true for anything that isn't a call note, and for a call note that
    /// is news (`isNews`).
    static func isNews(_ event: Event) -> Bool {
        guard event.type == "m.room.message", let call = of(event.content) else { return true }
        return call.isNews
    }

    /// Who to name beside a call note: in a group, the caller; in a one-to-one chat, no one (it can only be them).
    /// Nil for my own call and for any other message.
    public static func caller(of message: TimelineMessage, direct: Bool) -> String? {
        guard message.call != nil, !message.mine, !direct else { return nil }
        let name = message.senderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The symbol a call note is drawn with: a video camera or a phone, crossed out when it went unanswered or wrong.
    public var symbol: String {
        let failed = state == .missed || state == .declined || state == .dropped
        switch media {
        case .video: return failed ? "video.slash" : "video"
        default: return failed ? "phone.down" : "phone"
        }
    }
}
