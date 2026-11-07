// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import CourierCore
import Foundation

/// A scenario of made-up chats (apps/desktop/courier/seed/scenarios), the same files the test copy's engine plays:
/// one chat of it becomes the events the engine would send for it, with Fixture.now as "now". Format: the seed
/// folder's README.md.
struct SeedScenario: Decodable {
    struct Person: Decodable {
        let id: String
        let name: String
    }

    struct Reaction: Decodable {
        let from: String
        let emoji: String
    }

    struct Message: Decodable {
        let id: String
        let from: String
        let minutesAgo: Int
        let text: String
        let replyTo: String?
        let thread: String?
        let reactions: [Reaction]?
    }

    struct Chat: Decodable {
        let account: String
        let id: String
        let name: String?
        let direct: Bool?
        let messages: [Message]
    }

    let people: [Person]
    let chats: [Chat]

    enum Failure: Error, CustomStringConvertible {
        case notFound(String, [String])
        case noChat(String)

        var description: String {
            switch self {
            case let .notFound(name, tried): "seed scenario \(name) not found; tried \(tried)"
            case let .noChat(id): "the scenario has no chat \(id)"
            }
        }
    }

    /// The scenario folder: Bazel's runfiles (BUILD's data on //apps/desktop/courier/seed:scenarios), or, under
    /// SwiftPM, the source tree beside this file.
    static func directoryCandidates() -> [URL] {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [URL] = []
        if let runfiles = environment["TEST_SRCDIR"] {
            for workspace in [environment["TEST_WORKSPACE"], "_main"].compactMap({ $0 }) {
                candidates.append(URL(fileURLWithPath: "\(runfiles)/\(workspace)/apps/desktop/courier/seed/scenarios"))
            }
        }
        // Tests/CourierViewTests/SeedScenario.swift → apps/desktop/courier/seed/scenarios
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("seed/scenarios"))
        return candidates
    }

    static func load(_ name: String) throws -> SeedScenario {
        let files = directoryCandidates().map { $0.appendingPathComponent("\(name).json") }
        guard let file = files.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw Failure.notFound(name, files.map(\.path))
        }
        return try JSONDecoder().decode(SeedScenario.self, from: Data(contentsOf: file))
    }

    func name(of person: String) -> String {
        people.first { $0.id == person }?.name ?? person
    }

    static func eventID(_ messageID: String) -> String { "$\(messageID)" }

    static func userID(_ person: String) -> String { "@\(person):courier.local" }

    /// The chat's main timeline as the engine pages it, oldest first: its messages with their replies, and each
    /// thread's root carrying its summary, but not the replies that stay in a thread (the thread pane shows those),
    /// then every reaction.
    func events(chat id: String) throws -> [Event] {
        guard let chat = chats.first(where: { $0.id == id }) else { throw Failure.noChat(id) }
        // Oldest first; messages of the same minute keep the file's order, as the engine plays them.
        let ordered = chat.messages.enumerated().sorted {
            ($0.element.minutesAgo, -$0.offset) > ($1.element.minutesAgo, -$1.offset)
        }.map(\.element)
        var threads: [String: [Message]] = [:]
        for message in ordered {
            if let root = message.thread { threads[root, default: []].append(message) }
        }
        var events: [Event] = []
        for message in ordered where message.thread == nil {
            var summary: ThreadSummary?
            if let replies = threads[message.id], let last = replies.last {
                var senders: [String] = []
                for reply in replies.reversed() where reply.from != "me" {
                    let who = name(of: reply.from)
                    if !senders.contains(who) { senders.append(who) }
                }
                summary = ThreadSummary(replies: replies.count, lastTS: Fixture.millis(last.minutesAgo),
                                        lastSenders: Array(senders.prefix(3)))
            }
            var content: [String: JSONValue] = ["msgtype": .string("m.text"), "body": .string(message.text)]
            if let target = message.replyTo {
                content["m.relates_to"] = .object(["m.in_reply_to": .object(["event_id": .string(Self.eventID(target))])])
            }
            let mine = message.from == "me"
            events.append(Fixture.event(Self.eventID(message.id), mine: mine, ts: message.minutesAgo, content: content,
                                        thread: summary, sender: mine ? nil : Self.userID(message.from),
                                        name: name(of: message.from)))
        }
        for message in ordered where message.thread == nil {
            for (index, reaction) in (message.reactions ?? []).enumerated() {
                let mine = reaction.from == "me"
                events.append(Fixture.event("\(Self.eventID(message.id))-r\(index)", type: "m.reaction", mine: mine,
                                            ts: message.minutesAgo, content: [
                                                "m.relates_to": .object([
                                                    "rel_type": .string("m.annotation"),
                                                    "event_id": .string(Self.eventID(message.id)),
                                                    "key": .string(reaction.emoji),
                                                ]),
                                            ], sender: mine ? nil : Self.userID(reaction.from),
                                            name: name(of: reaction.from)))
            }
        }
        return events
    }
}
