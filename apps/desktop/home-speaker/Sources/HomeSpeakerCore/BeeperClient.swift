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

// Beeper Desktop's local HTTP API, read-only. Beeper bridges WhatsApp,
// Signal, Telegram, Google Messages, Slack and more into one app on this
// Mac, and serves them on http://localhost:23373 to whoever holds a token
// made in its Settings › Integrations. HomeSpeaker asks it two things, both
// GET: the accounts (once at start, and again when a message names one it
// has not seen), and the messages after a date (once a poll). It never sends
// anything else, and never sends the token anywhere but this Mac.

/// One network account inside Beeper.
public struct BeeperAccount: Equatable, Sendable {
    public var accountID: String
    /// The bridge's own name for itself ("slackgo", "whatsapp"), when Beeper
    /// says; older Beeper Desktops do not.
    public var bridgeType: String?
    /// The network's name, for people: "WhatsApp", "Slack".
    public var network: String
    /// Your own id on that network, as `mentions` names you.
    public var userID: String?

    public init(accountID: String, bridgeType: String? = nil, network: String, userID: String? = nil) {
        self.accountID = accountID
        self.bridgeType = bridgeType
        self.network = network
        self.userID = userID
    }
}

/// One chat a message is in, as the search's `chats` map gives it.
public struct BeeperChat: Equatable, Sendable {
    public var id: String
    /// True for a one-to-one chat (`type == "single"`).
    public var isDirect: Bool
    public var title: String
    /// Display only: never used to decide anything.
    public var network: String?
    public var isMuted: Bool
    public var isLowPriority: Bool

    public init(id: String, isDirect: Bool, title: String = "", network: String? = nil,
                isMuted: Bool = false, isLowPriority: Bool = false) {
        self.id = id
        self.isDirect = isDirect
        self.title = title
        self.network = network
        self.isMuted = isMuted
        self.isLowPriority = isLowPriority
    }
}

/// One message from the search.
public struct BeeperMessage: Equatable, Sendable {
    public var id: String
    public var chatID: String
    public var accountID: String
    public var senderID: String
    public var senderName: String
    public var timestamp: Date
    /// TEXT, NOTICE, IMAGE, VIDEO, VOICE, AUDIO, FILE, STICKER, LOCATION,
    /// REACTION, upper case as Beeper writes them.
    public var type: String
    public var text: String
    public var isSender: Bool
    public var isHidden: Bool
    public var isDeleted: Bool
    /// The ids mentioned, and `@room` for everyone.
    public var mentions: [String]

    public init(id: String, chatID: String, accountID: String, senderID: String = "", senderName: String = "",
                timestamp: Date, type: String = "TEXT", text: String = "", isSender: Bool = false,
                isHidden: Bool = false, isDeleted: Bool = false, mentions: [String] = []) {
        self.id = id
        self.chatID = chatID
        self.accountID = accountID
        self.senderID = senderID
        self.senderName = senderName
        self.timestamp = timestamp
        self.type = type
        self.text = text
        self.isSender = isSender
        self.isHidden = isHidden
        self.isDeleted = isDeleted
        self.mentions = mentions
    }

    /// Unique across chats: Beeper's ids are a chat's own.
    public var key: String { "\(chatID)/\(id)" }
}

/// What one search returned.
public struct BeeperSearch: Equatable, Sendable {
    public var messages: [BeeperMessage]
    public var chats: [String: BeeperChat]
    /// More messages match than this page holds.
    public var hasMore = false
    /// Where the next page starts, older or newer than this one.
    public var oldestCursor: String?
    public var newestCursor: String?
    /// Beeper sent this page newest first (its order is not documented,
    /// so it is read from the page itself).
    public var newestFirst = true

    public init(messages: [BeeperMessage], chats: [String: BeeperChat], hasMore: Bool = false,
                oldestCursor: String? = nil, newestCursor: String? = nil, newestFirst: Bool = true) {
        self.messages = messages
        self.chats = chats
        self.hasMore = hasMore
        self.oldestCursor = oldestCursor
        self.newestCursor = newestCursor
        self.newestFirst = newestFirst
    }
}

/// Every page a poll read, merged.
public struct BeeperPages: Equatable, Sendable {
    public var messages: [BeeperMessage]
    public var chats: [String: BeeperChat]
    /// Pages read.
    public var pages: Int
    /// Reading stopped with more to read, after `unseenBudget` messages
    /// that count (new, and to be spoken or not yet known), or at the
    /// `maxPages` safety bound: some may have been missed.
    public var truncated: Bool
}

public struct BeeperClient: Sendable {
    /// Beeper Desktop's API on this Mac. `localhost`, not `127.0.0.1`: App
    /// Transport Security refuses plain HTTP to an address written as
    /// numbers, and allows it to localhost.
    public static let defaultBaseURL = URL(string: "http://localhost:23373")!
    /// Names another address, for tests only. Taken only for this Mac
    /// (loopback), so a token can never leave it.
    public static let urlVariable = "HOMESPEAKER_BEEPER_URL"
    /// How far back each poll looks again, for a message that arrived late.
    public static let lookBack: TimeInterval = 5 * 60
    /// The most one search returns (the API's own limit).
    public static let pageLimit = 20
    /// The most new messages to be spoken one poll reads: past these, with
    /// more still to read, the poll says some may be missed.
    public static let unseenBudget = 200
    /// The most pages one poll reads whatever they hold (1000 messages): a
    /// safety bound, for a window full of messages already handled or
    /// skipped.
    public static let maxPages = 50

    let token: String
    public let baseURL: URL
    let session: URLSession

    public init(token: String, baseURL: URL = BeeperClient.defaultBaseURL, session: URLSession = BeeperClient.makeSession()) {
        self.token = token
        self.baseURL = baseURL
        self.session = session
    }

    /// A session of its own: five seconds to answer, no proxy, no cookies,
    /// no cache. Beeper is on this Mac, so a slow answer means it is stuck.
    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        configuration.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: false,
            kCFNetworkProxiesHTTPSEnable as String: false,
        ]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// Where Beeper is: `defaultBaseURL`, or `HOMESPEAKER_BEEPER_URL` when
    /// that names an http address on this Mac. Any other value is refused,
    /// and Beeper is not read at all, rather than falling back to the real
    /// Beeper on this Mac.
    public static func baseURL(environment: [String: String]) -> Result<URL, ChatMonitorError> {
        guard let named = environment[urlVariable], !named.isEmpty else { return .success(defaultBaseURL) }
        guard let url = URL(string: named), url.scheme == "http", isLoopback(url) else {
            return .failure(.beeper("\(urlVariable) must be an http address on this Mac, not \(named)"))
        }
        return .success(url)
    }

    /// The address is this Mac's own.
    public static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    // MARK: Requests

    /// Your accounts, each network you have in Beeper.
    public func accounts() async throws -> [BeeperAccount] {
        Self.parseAccounts(try await get("v1/accounts", query: []))
    }

    /// Messages strictly after `after`, at most `pageLimit`, from chats that
    /// are not muted or low priority; only other people's when `othersOnly`.
    /// One page: `cursor` and `direction` ("before" for older, "after" for
    /// newer) carry on from the page before.
    public func messages(after: Date, othersOnly: Bool, cursor: String? = nil, direction: String? = nil) async throws -> BeeperSearch {
        var query = [
            URLQueryItem(name: "dateAfter", value: ISO8601DateFormatter.fractional.string(from: after)),
            URLQueryItem(name: "limit", value: String(Self.pageLimit)),
            URLQueryItem(name: "includeMuted", value: "false"),
            URLQueryItem(name: "excludeLowPriority", value: "true"),
        ]
        if othersOnly { query.append(URLQueryItem(name: "sender", value: "others")) }
        if let cursor, let direction {
            query.append(URLQueryItem(name: "cursor", value: cursor))
            query.append(URLQueryItem(name: "direction", value: direction))
        }
        let json = try await get("v1/messages/search", query: query)
        return Self.parseSearch((json as? [String: Any]) ?? [:])
    }

    /// Every message after `after`, page by page. Each page carries on from
    /// the last in the order Beeper sent it: older when it came newest
    /// first, newer when oldest first. Stops when Beeper has no more, at a
    /// page with nothing new, or a cursor already used; and, with more
    /// still to read (`truncated`), once `unseenBudget` messages that
    /// `counts` have been read, or at `maxPages`. Messages already handled,
    /// or skipped, do not count, so a busy window of those is no alarm.
    public func allMessages(
        after: Date, othersOnly: Bool, unseenBudget: Int = BeeperClient.unseenBudget, maxPages: Int = BeeperClient.maxPages,
        counts: @Sendable (BeeperMessage, BeeperChat?) -> Bool = { _, _ in true }
    ) async throws -> BeeperPages {
        var messages: [String: BeeperMessage] = [:]
        var chats: [String: BeeperChat] = [:]
        var cursor: String?
        var direction: String?
        var used: Set<String> = []
        var pages = 0
        var counted = 0
        while true {
            let page = try await self.messages(after: after, othersOnly: othersOnly, cursor: cursor, direction: direction)
            pages += 1
            let before = messages.count
            chats.merge(page.chats) { _, new in new }
            for message in page.messages where messages[message.key] == nil {
                messages[message.key] = message
                if counts(message, chats[message.chatID]) { counted += 1 }
            }
            let next = page.newestFirst ? page.oldestCursor : page.newestCursor
            guard page.hasMore, messages.count > before, let next, !used.contains(next) else { break }
            guard counted < unseenBudget, pages < maxPages else {
                return BeeperPages(messages: Self.sorted(messages.values), chats: chats, pages: pages, truncated: true)
            }
            used.insert(next)
            cursor = next
            direction = page.newestFirst ? "before" : "after"
        }
        return BeeperPages(messages: Self.sorted(messages.values), chats: chats, pages: pages, truncated: false)
    }

    static func sorted<S: Sequence>(_ messages: S) -> [BeeperMessage] where S.Element == BeeperMessage {
        messages.sorted { ($0.timestamp, $0.key) < ($1.timestamp, $1.key) }
    }

    /// The one way a request is made: GET, with the token, to this Mac.
    private func get(_ path: String, query: [URLQueryItem]) async throws -> Any {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url, Self.isLoopback(url) else {
            throw ChatMonitorError.beeper("refused to send the Beeper token anywhere but this Mac")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RefuseRedirects())
        } catch let error as URLError {
            throw Self.mapped(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        switch status {
        case 200: return json ?? [:]
        case 401: throw ChatMonitorError.beeperTokenRefused
        case 429: throw ChatMonitorError.beeperSlowDown
        case 300..<400: throw ChatMonitorError.beeper("Beeper Desktop answered with a redirect, which HomeSpeaker does not follow")
        default:
            let message = ((json as? [String: Any])?["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            throw ChatMonitorError.beeper(message ?? "HTTP \(status)")
        }
    }

    /// Nothing listening is Beeper not running, or its API switched off.
    static func mapped(_ error: URLError) -> ChatMonitorError {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet:
            return .beeperNotRunning
        case .timedOut:
            return .beeper("Beeper Desktop did not answer within 5 seconds")
        case .appTransportSecurityRequiresSecureConnection:
            return .beeper("macOS refused a plain connection to Beeper Desktop on this Mac (App Transport Security)")
        default:
            return .beeper(error.localizedDescription)
        }
    }

    // MARK: Reading the answers (pure)

    /// `GET /v1/accounts`: a list, or an object holding one under `items`
    /// or `accounts`. An entry with no id is skipped.
    public static func parseAccounts(_ json: Any) -> [BeeperAccount] {
        let list: [[String: Any]]
        if let array = json as? [[String: Any]] {
            list = array
        } else if let object = json as? [String: Any] {
            list = (object["items"] as? [[String: Any]]) ?? (object["accounts"] as? [[String: Any]]) ?? []
        } else {
            list = []
        }
        return list.compactMap { entry in
            guard let id = entry["accountID"] as? String, !id.isEmpty else { return nil }
            let bridge = entry["bridge"] as? [String: Any]
            let user = entry["user"] as? [String: Any]
            return BeeperAccount(
                accountID: id, bridgeType: bridge?["type"] as? String,
                network: (entry["network"] as? String) ?? "", userID: user?["id"] as? String)
        }
    }

    /// `GET /v1/messages/search`: `items` and the `chats` they are in.
    /// Messages without an id, a chat or a readable time are skipped;
    /// the rest come back oldest first, whatever order Beeper sent.
    public static func parseSearch(_ json: [String: Any]) -> BeeperSearch {
        var chats: [String: BeeperChat] = [:]
        for (key, value) in (json["chats"] as? [String: Any]) ?? [:] {
            guard let chat = value as? [String: Any] else { continue }
            let id = (chat["id"] as? String) ?? key
            chats[id] = BeeperChat(
                id: id, isDirect: (chat["type"] as? String) == "single", title: (chat["title"] as? String) ?? "",
                network: chat["network"] as? String, isMuted: (chat["isMuted"] as? Bool) ?? false,
                isLowPriority: (chat["isLowPriority"] as? Bool) ?? false)
        }
        let inOrder = ((json["items"] as? [[String: Any]]) ?? []).compactMap { m -> BeeperMessage? in
            guard let id = m["id"] as? String, let chatID = m["chatID"] as? String,
                  let stamp = m["timestamp"] as? String, let date = parseDate(stamp) else { return nil }
            return BeeperMessage(
                id: id, chatID: chatID, accountID: (m["accountID"] as? String) ?? "",
                senderID: (m["senderID"] as? String) ?? "", senderName: (m["senderName"] as? String) ?? "",
                timestamp: date, type: ((m["type"] as? String) ?? "TEXT").uppercased(), text: (m["text"] as? String) ?? "",
                isSender: (m["isSender"] as? Bool) ?? false, isHidden: (m["isHidden"] as? Bool) ?? false,
                isDeleted: (m["isDeleted"] as? Bool) ?? false, mentions: (m["mentions"] as? [String]) ?? [])
        }
        let newestFirst = (inOrder.first?.timestamp ?? .distantFuture) >= (inOrder.last?.timestamp ?? .distantPast)
        return BeeperSearch(
            messages: sorted(inOrder), chats: chats, hasMore: (json["hasMore"] as? Bool) ?? false,
            oldestCursor: json["oldestCursor"] as? String, newestCursor: json["newestCursor"] as? String,
            newestFirst: newestFirst)
    }

    static func parseDate(_ text: String) -> Date? {
        ISO8601DateFormatter.fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    // MARK: Which network an account is

    /// What an account is, for the duplicates rule.
    public enum Kind: Equatable, Sendable {
        /// A Slack workspace; `team` is its id (T…), when the account id says.
        case slack(team: String?)
        case googleChat
        case other
    }

    /// The bridge's type first, then the account id's prefix, then the
    /// network's name: the first that says Slack or Google Chat decides.
    /// Google Messages (`gmessages`, texts and RCS) is never Google Chat.
    public static func classify(_ account: BeeperAccount) -> Kind {
        let bridge = (account.bridgeType ?? "").lowercased()
        let id = account.accountID.lowercased()
        let network = account.network.lowercased()
        let slack = Kind.slack(team: slackTeam(accountID: account.accountID))
        if bridge.contains("slack") { return slack }
        if bridge.contains("googlechat") || bridge == "gchat" { return .googleChat }
        if id.hasPrefix("slack") || id.hasPrefix("local-slack") { return slack }
        if id.hasPrefix("googlechat") || id.hasPrefix("local-googlechat") || id.hasPrefix("gchat") { return .googleChat }
        if network == "slack" { return slack }
        if network == "google chat" || network == "googlechat" { return .googleChat }
        return .other
    }

    /// `slackgo.T0123-U0456` → `U0456`; nil for any other shape.
    public static func slackUser(accountID: String) -> String? {
        guard accountID.lowercased().hasPrefix("slackgo."), let dash = accountID.firstIndex(of: "-") else { return nil }
        let user = String(accountID[accountID.index(after: dash)...])
        return user.isEmpty ? nil : user
    }

    /// `slackgo.T0123-U0456` → `T0123`; nil for any other shape, which
    /// the duplicates rule treats as the workspace HomeSpeaker reads.
    public static func slackTeam(accountID: String) -> String? {
        let prefix = "slackgo."
        guard accountID.lowercased().hasPrefix(prefix) else { return nil }
        let rest = accountID.dropFirst(prefix.count)
        guard let dash = rest.firstIndex(of: "-") else { return nil }
        let team = String(rest[..<dash])
        return team.isEmpty ? nil : team
    }

    /// The accounts HomeSpeaker leaves to its own reader, so nothing is
    /// spoken twice: while its Slack switch is on, Beeper's Slack accounts
    /// for the workspace the Slack token reads (`nativeSlackTeam`), or every
    /// Slack account when that workspace is not known; while its Google
    /// Chat switch is on, Beeper's Google Chat accounts. The Slack user id
    /// (`nativeSlackUser`, from the same `auth.test`) matching counts too:
    /// Slack user ids are a workspace's own, and an Enterprise Grid account
    /// may carry its grid's id where the team goes.
    public static func isSkipped(
        _ account: BeeperAccount, config: ChatMonitorConfig, nativeSlackTeam: String?, nativeSlackUser: String? = nil
    ) -> Bool {
        switch classify(account) {
        case .slack(let team):
            guard config.slackEnabled else { return false }
            if let nativeSlackUser, slackUser(accountID: account.accountID) == nativeSlackUser { return true }
            guard let nativeSlackTeam, let team else { return true }
            return team == nativeSlackTeam
        case .googleChat:
            return config.googleChatEnabled
        case .other:
            return false
        }
    }

    // MARK: Which messages are spoken, and how

    /// Direct messages; group messages that mention you (one of your
    /// accounts' ids, or `@room`), or every one with `.all`. Never a
    /// reaction, a hidden or deleted message, one from a muted or
    /// low-priority chat, or, with `muteOwn`, one you sent.
    public static func shouldAnnounce(
        _ message: BeeperMessage, chat: BeeperChat?, ownUserIDs: Set<String>,
        mode: ChatMonitorConfig.BeeperAnnounce, muteOwn: Bool
    ) -> Bool {
        if message.type == "REACTION" || message.isHidden || message.isDeleted { return false }
        if muteOwn && (message.isSender || ownUserIDs.contains(message.senderID)) { return false }
        if chat?.isMuted == true || chat?.isLowPriority == true { return false }
        if chat?.isDirect == true || mode == .all { return true }
        return message.mentions.contains("@room") || message.mentions.contains { ownUserIDs.contains($0) }
    }

    /// What is said of the message: its text, or what was sent when it is
    /// a photo or the like ("sent a photo: caption"). Nil when there is
    /// nothing to say.
    public static func spokenText(_ message: BeeperMessage) -> String? {
        let text = message.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let sent: String?
        switch message.type {
        case "IMAGE": sent = "sent a photo"
        case "VIDEO": sent = "sent a video"
        case "VOICE": sent = "sent a voice message"
        case "AUDIO": sent = "sent an audio file"
        case "FILE": sent = "sent a file"
        case "STICKER": sent = "sent a sticker"
        case "LOCATION": sent = "shared a location"
        default: sent = nil
        }
        guard let sent else { return text.isEmpty ? nil : text }
        return text.isEmpty ? sent : "\(sent): \(text)"
    }

    /// The message as the monitor speaks it: "WhatsApp message from Alice:
    /// …", with the group's name for a group.
    public static func incoming(_ message: BeeperMessage, chat: BeeperChat?, account: BeeperAccount?, text: String) -> IncomingMessage {
        let network = [account?.network, chat?.network].compactMap { $0 }.first { !$0.isEmpty }
        return IncomingMessage(
            source: .beeper, id: "beeper/\(message.key)", timestamp: message.timestamp,
            senderId: message.senderID, senderName: message.senderName,
            channel: chat?.isDirect == true ? "" : (chat?.title ?? ""), text: text, network: network)
    }
}

/// Answers every redirect with "no": the token goes to this Mac's Beeper
/// and is never carried on to wherever a redirect points.
final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
