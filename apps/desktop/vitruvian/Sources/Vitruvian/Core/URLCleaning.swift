// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

package enum URLCleaning {
    private static let trackedParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_viz_id", "utm_pubreferrer",
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
        "mc_cid", "mc_eid", "igshid", "twclid", "ttclid", "li_fat_id",
        "mkt_tok", "_hsenc", "_hsmi", "__twitter_impression",
        "fb_action_ids", "fb_action_types", "fb_source", "mibextid",
    ]

    /// Trackers that only one site uses. A global list cannot hold these: `si`
    /// is a share token on YouTube but a real parameter elsewhere, and `t` is a
    /// tracker on X while it is the playback position on YouTube. Matching on
    /// the host is what keeps removing one from breaking the other.
    ///
    /// Keys match the host itself or any subdomain of it.
    private static let hostParameters: [String: Set<String>] = [
        "youtube.com": ["si", "pp", "feature", "kw"],
        "youtu.be": ["si", "pp", "feature", "kw"],
        "twitter.com": ["s", "t", "cn", "src", "refsrc", "ref_src", "ref_url"],
        "x.com": ["s", "t", "cn", "src", "refsrc", "ref_src", "ref_url"],
        "instagram.com": ["igsh"],
        "spotify.com": ["si"],
        // Reddit's share sheet routes through branch.io, whose deep link fields
        // start with a literal `$`. Links often carry them percent-encoded as
        // `%24…`, but only the decoded spelling is listed: `decodedName` decodes
        // the name half of each pair before the rules see it. ClearURLs lists
        // both because it matches the raw query with regex.
        "reddit.com": [
            "correlation_id", "ref_campaign", "ref_source", "rdt", "share_id",
            "_branch_match_id", "$deep_link", "$3p", "$original_url",
        ],
        "tiktok.com": [
            "u_code", "preview_pb", "_d", "_t", "_r", "timestamp", "user_id",
            "share_app_name", "share_iid",
        ],
        "bilibili.com": [
            "spm_id_from", "from_spmid", "from_source", "share_source", "share_from",
            "share_medium", "share_plat", "share_tag", "share_session_id", "msource",
            "refer_from", "seid", "unique_k", "vd_source", "plat_id", "buvid", "bbid",
            "up_id", "is_story_h5", "timestamp", "ts", "visit_id", "session_id",
            "broadcast_type", "is_room_feed",
        ],
        "xiaohongshu.com": [
            "xhsshare", "author_share", "xsec_source", "share_from_user_hidden",
            "shareredid", "share_id", "exsource", "app_version", "app_platform",
            "apptime", "appuid",
        ],
    ]

    /// A cleaned link and the names taken out of it, so every surface that
    /// cleans can say what it removed instead of only that something changed.
    package struct Result: Equatable {
        package let url: String
        package let removed: [String]

        // Spelled out because a memberwise initializer never leaves its module.
        package init(url: String, removed: [String]) {
            self.url = url
            self.removed = removed
        }
    }

    /// What the user changed about the tables above: names they added, and
    /// built-in names they switched off. Stored as a difference rather than a
    /// copy of the tables, so names added in a later version of the app still
    /// reach someone who has already edited their rules.
    ///
    /// Both maps are keyed the way `hostParameters` is, with `allSites` for
    /// the rules that apply everywhere.
    package struct Rules: Equatable {
        package var added: [String: Set<String>] = [:]
        package var disabled: [String: Set<String>] = [:]

        package static let none = Rules()

        // Spelled out because a memberwise initializer never leaves its module.
        package init(added: [String: Set<String>] = [:], disabled: [String: Set<String>] = [:]) {
            self.added = added
            self.disabled = disabled
        }
    }

    /// One row of a site's rules, as Settings shows it.
    package struct RuleGroup: Identifiable, Equatable {
        package let site: String
        package let entries: [Entry]

        package var id: String { site }
        package var enabledCount: Int { entries.filter(\.isEnabled).count }

        package struct Entry: Identifiable, Equatable {
            package let name: String
            package let isBuiltIn: Bool
            package let isEnabled: Bool

            package var id: String { name }

            // Spelled out because a memberwise initializer never leaves its module.
            package init(name: String, isBuiltIn: Bool, isEnabled: Bool) {
                self.name = name
                self.isBuiltIn = isBuiltIn
                self.isEnabled = isEnabled
            }
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(site: String, entries: [Entry]) {
            self.site = site
            self.entries = entries
        }
    }

    /// The key the global rules live under. Empty so a stored token reads as
    /// `|ref` for a global name and `youtube.com|si` for a site one.
    package static let allSites = ""

    /// The single row standing for every `utm_` name. The cleaner matches the
    /// prefix, so listing `utm_source` and its siblings separately would show
    /// rows that cannot be switched off on their own.
    package static let utmWildcard = "utm_*"

    /// The global list as Settings shows it: the wildcard row, then the names
    /// the prefix does not already cover.
    package static var globalBuiltInNames: [String] {
        [utmWildcard] + trackedParameters.filter { !$0.hasPrefix("utm_") }.sorted()
    }

    /// What a surface says after cleaning. The choice lives here so the
    /// Settings page, the menu panel and the Command Bar action cannot drift
    /// apart, and so it can be pinned without a view.
    package enum Outcome: Equatable {
        case notAURL
        case unchanged
        case rewritten
        case removed([String])
    }

    package static func outcome(for result: Result?, input: String) -> Outcome {
        guard let result else { return .notAURL }
        guard result.removed.isEmpty else { return .removed(result.removed) }
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.url == trimmed ? .unchanged : .rewritten
    }

    /// Reads the three stored strings into one value. The global additions
    /// keep the plain comma-separated key they have always used, so nothing
    /// has to be migrated when site rules arrive.
    package static func rules(globalNames: String?, siteNames: String?, disabledNames: String?) -> Rules {
        var added = tokens(from: siteNames)
        added[allSites] = customParameters(from: globalNames)
        added = added.filter { !$0.value.isEmpty }
        return Rules(added: added, disabled: tokens(from: disabledNames).filter { !$0.value.isEmpty })
    }

    package static func clean(_ text: String, rules: Rules = .none) -> Result? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = components.host,
              components.url != nil else {
            return nil
        }

        // URLComponents validates the link and supplies its host, but can
        // re-encode existing escapes when a query also contains literal Unicode.
        // Slice the original text by scalars so combining marks cannot hide
        // a query delimiter inside a Character.
        let scalars = trimmed.unicodeScalars
        let fragmentStart = scalars.firstIndex(of: "#") ?? scalars.endIndex
        guard let queryStart = scalars[..<fragmentStart].firstIndex(of: "?") else {
            return Result(url: trimmed, removed: [])
        }
        let query = scalars[scalars.index(after: queryStart)..<fragmentStart]
        var removed: [String] = []
        let matcher = Self.matcher(for: host, rules: rules)
        let kept = query.split(separator: "&", omittingEmptySubsequences: false)
            .filter { pair in
                let name = Self.decodedName(ofRawPair: pair)
                guard matcher.matches(name) else { return true }
                if !removed.contains(name) { removed.append(name) }
                return false
            }
        guard !removed.isEmpty else {
            return Result(url: trimmed, removed: [])
        }

        let survivingQuery = kept.map { String($0) }.joined(separator: "&")
        let url = String(scalars[..<queryStart])
            + (kept.isEmpty ? "" : "?" + survivingQuery)
            + String(scalars[fragmentStart...])
        return Result(url: url, removed: removed)
    }

    package static func ruleGroups(rules: Rules) -> [RuleGroup] {
        let sites = Set(hostParameters.keys)
            .union(rules.added.keys)
            .union(rules.disabled.keys)
            .subtracting([allSites])
        let groups = [group(for: allSites, builtIn: globalBuiltInNames, rules: rules)]
            + sites.sorted().map {
                group(for: $0, builtIn: (hostParameters[$0] ?? []).sorted(), rules: rules)
            }
        return groups.filter { !$0.entries.isEmpty }
    }

    /// The three stored lists the rules come from, as the Settings rules list
    /// edits them: as a difference from the built-in tables, each edit
    /// touching only the names it is about.
    package struct StoredRules: Equatable {
        package var globalNames: String
        package var siteNames: String
        package var disabledNames: String

        // Spelled out because a memberwise initializer never leaves its module.
        package init(globalNames: String = "", siteNames: String = "", disabledNames: String = "") {
            self.globalNames = globalNames
            self.siteNames = siteNames
            self.disabledNames = disabledNames
        }

        package var rules: Rules {
            URLCleaning.rules(globalNames: globalNames, siteNames: siteNames, disabledNames: disabledNames)
        }

        /// Off switches off every name the row lists, the user's own included,
        /// so on can clear the row's record and turn every name it lists on
        /// again, one switched off by hand before included.
        package mutating func setSite(_ group: RuleGroup, enabled: Bool) {
            var disabled = URLCleaning.tokens(from: disabledNames)
            disabled[group.site] = enabled ? nil : Set(group.entries.map(\.name))
            disabledNames = URLCleaning.storageValue(forTokens: disabled)
        }

        /// Deletes a name the user added. It takes its switched off record
        /// with it, so adding it again later brings it back on, as typing it
        /// back in already does.
        package mutating func remove(_ name: String, from site: String) {
            var disabled = URLCleaning.tokens(from: disabledNames)
            disabled[site]?.remove(name)
            disabledNames = URLCleaning.storageValue(forTokens: disabled)
            if site == URLCleaning.allSites {
                var names = URLCleaning.customParameters(from: globalNames)
                names.remove(name)
                globalNames = URLCleaning.storageValue(forNames: names)
            } else {
                var added = URLCleaning.tokens(from: siteNames)
                added[site]?.remove(name)
                siteNames = URLCleaning.storageValue(forTokens: added)
            }
        }
    }

    /// Comma-separated names, the format the global custom list has always
    /// been stored in.
    package static func customParameters(from storedValue: String?) -> Set<String> {
        Set(split(storedValue).map { $0.lowercased() })
    }

    package static func storageValue(forNames names: Set<String>) -> String {
        names.sorted().joined(separator: ", ")
    }

    /// `host|name` tokens, used by both the site additions and the switched
    /// off built-ins.
    package static func tokens(from storedValue: String?) -> [String: Set<String>] {
        var map: [String: Set<String>] = [:]
        for token in split(storedValue) {
            let parts = token.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = String(parts[1]).lowercased()
            guard !name.isEmpty else { continue }
            map[String(parts[0]).lowercased(), default: []].insert(name)
        }
        return map
    }

    package static func storageValue(forTokens map: [String: Set<String>]) -> String {
        map.keys.sorted()
            .flatMap { site in (map[site] ?? []).sorted().map { "\(site)|\($0)" } }
            .joined(separator: ",")
    }

    /// Accepts what someone is likely to paste into the site field — a bare
    /// host, a `www.` host or a whole link — and answers with the host key the
    /// rules are stored under, or nil when it is not a host at all.
    package static func siteKey(from text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = value.range(of: "://") {
            value = String(value[scheme.upperBound...])
        }
        if let end = value.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" }) {
            value = String(value[..<end])
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        guard value.contains("."), !value.hasPrefix("."), !value.hasSuffix("."),
              value.allSatisfy({ !$0.isWhitespace && $0 != "|" && $0 != "," }) else {
            return nil
        }
        return value
    }

    /// A name is a single query parameter, so anything a query cannot carry as
    /// one name is rejected rather than silently stored.
    package static func parameterName(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty,
              value.allSatisfy({ !$0.isWhitespace && $0 != "|" && $0 != "," && $0 != "&" && $0 != "=" }) else {
            return nil
        }
        return value
    }

    /// The name half of one percent-encoded `name=value` pair, decoded so a
    /// tracker a link spells as `%75tm_source` or `%24deep_link` is still the
    /// name the rules list. A pair carrying no `=` is a bare flag, so the
    /// whole pair is its name and is matched like any other: a lone
    /// `utm_source` goes, which is what the link dropping the pair meant. Only
    /// an escape that will not decode at all falls back to the raw text, and
    /// even that is matched as written — `utm_%ff` still answers to the
    /// `utm_` prefix.
    private static func decodedName(ofRawPair pair: String.UnicodeScalarView.SubSequence) -> String {
        let raw = String(pair.prefix { $0 != "=" })
        guard raw.contains("%") else { return raw }
        return raw.removingPercentEncoding ?? raw
    }

    private struct Matcher {
        let names: Set<String>
        let matchesUTMPrefix: Bool

        func matches(_ name: String) -> Bool {
            let normalized = name.lowercased()
            return names.contains(normalized) || (matchesUTMPrefix && normalized.hasPrefix("utm_"))
        }

        // Spelled out because a memberwise initializer never leaves its module.
        package init(names: Set<String>, matchesUTMPrefix: Bool) {
            self.names = names
            self.matchesUTMPrefix = matchesUTMPrefix
        }
    }

    private static func matcher(for host: String, rules: Rules) -> Matcher {
        let disabledGlobally = rules.disabled[allSites] ?? []
        var names = trackedParameters.filter {
            !$0.hasPrefix("utm_") && !disabledGlobally.contains($0)
        }
        names.formUnion((rules.added[allSites] ?? []).subtracting(disabledGlobally))
        for site in siteKeys(matching: host, rules: rules) {
            let disabled = rules.disabled[site] ?? []
            names.formUnion((hostParameters[site] ?? []).filter { !disabled.contains($0) })
            names.formUnion((rules.added[site] ?? []).subtracting(disabled))
        }
        return Matcher(names: names, matchesUTMPrefix: !disabledGlobally.contains(utmWildcard))
    }

    /// Site rules are additive: `open.spotify.com` picks up the `spotify.com`
    /// set, and a host that matches nothing keeps only the global rules.
    private static func siteKeys(matching host: String, rules: Rules) -> [String] {
        let normalized = host.lowercased()
        return Set(hostParameters.keys).union(rules.added.keys).union(rules.disabled.keys)
            .filter { !$0.isEmpty && (normalized == $0 || normalized.hasSuffix("." + $0)) }
            .sorted()
    }

    private static func group(for site: String, builtIn: [String], rules: Rules) -> RuleGroup {
        let disabled = rules.disabled[site] ?? []
        let added = (rules.added[site] ?? []).subtracting(builtIn)
        let entries = builtIn.map {
            RuleGroup.Entry(name: $0, isBuiltIn: true, isEnabled: !disabled.contains($0))
        } + added.sorted().map {
            RuleGroup.Entry(name: $0, isBuiltIn: false, isEnabled: !disabled.contains($0))
        }
        return RuleGroup(site: site, entries: entries)
    }

    private static func split(_ storedValue: String?) -> [String] {
        (storedValue ?? "")
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Automatic rewrite

    /// Whether a copy's HTML adds nothing to the link `text` but formatting,
    /// so a rewrite that drops it loses nothing. When every anchor leads to
    /// this link, whatever the copy shows, such as the page title, goes like
    /// any formatting of it (#1760). A picture's markup, an anchor to another
    /// address, or markup without anchors that shows more than the link is
    /// kept, as the bare link would lose it (#1432).
    package static func markupAddsOnlyFormatting(_ rawHTML: String, to text: String) -> Bool {
        // A copy of one link is a few hundred bytes. Far larger markup is
        // left alone rather than searched on the shared pasteboard queue.
        guard rawHTML.utf8.count <= 64 * 1024 else { return false }
        // Browsers write the address they resolved, percent-encoded and
        // with a slash for an empty path, so links compare as addresses.
        // Case folds after parsing, which writes its escapes in upper case.
        func address(_ string: String) -> String {
            guard let url = URL(string: string),
                  var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return string.lowercased()
            }
            if components.path.isEmpty { components.path = "/" }
            return (components.string ?? string).lowercased()
        }
        let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let linkAddress = address(link)
        // Head, style, script and title are never shown, and a head links
        // the document's own files, not the copy. One left open ends at
        // the body or the end, and a tag never spans a '<', so markup that
        // never closes is read once instead of once per '<'.
        let shown = rawHTML.replacingOccurrences(
            of: #"<(head|style|script|title)\b[^<>]*>[\s\S]*?(?:</\1\s*>|(?=<body\b)|\z)"#,
            with: "", options: [.regularExpression, .caseInsensitive])
        let targets = shown.replacingOccurrences(of: "href=", with: "href=", options: .caseInsensitive)
            .components(separatedBy: "href=").dropFirst()
            .map { address(String($0.dropFirst().prefix { $0 != "\"" && $0 != "'" })
                .replacingOccurrences(of: "&amp;", with: "&")) }
        let html = rawHTML.lowercased()
        let visible = shown.lowercased().replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "<[^<>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let media = ["<img", "<video", "<audio", "<picture", "<svg", "<iframe", "<object", "<embed"]
        return !media.contains(where: html.contains) && targets.allSatisfy({ $0 == linkAddress })
            && (!targets.isEmpty || visible.isEmpty || visible == link.lowercased())
    }

    /// Whether the clipboard can be rewritten with a cleaned link without
    /// losing anything the user copied. The rewrite keeps only the text and
    /// the URL, so it is allowed when every type on the pasteboard is text, a
    /// link, or an app's private note about the copy, and refused when the
    /// pasteboard also carries content of its own: a picture, a file or a
    /// promise to deliver one, a document. A link next to such content is only
    /// its textual fallback (a browser's "Copy Image" also carries the image
    /// URL as text). A copy an app marked concealed or transient is not an
    /// ordinary copy either, and is left alone.
    package static func canRewritePasteboard(types: [String]) -> Bool {
        guard !types.isEmpty else { return false }
        return types.allSatisfy(typeSurvivesRewrite)
    }

    private static let plainPasteboardTypes: Set<String> = [
        "public.utf8-plain-text", "public.url", "public.url-name",
        "NSStringPboardType", "NSURLPboardType",
    ]

    /// Marks from the nspasteboard.org convention: concealed is a password
    /// manager handing over a secret, transient is content about to be put
    /// back by whoever placed it.
    private static let untouchablePasteboardTypes: Set<String> = [
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
    ]

    /// A file being copied or promised, under the names that are not types
    /// the system knows and would otherwise pass as private notes.
    private static let filePasteboardTypes: Set<String> = [
        "NSFilenamesPboardType",
        "com.apple.NSFilePromiseItemMetaData",
        "Apple files promise pasteboard type",
    ]

    private static func typeSurvivesRewrite(_ rawValue: String) -> Bool {
        if plainPasteboardTypes.contains(rawValue) { return true }
        if untouchablePasteboardTypes.contains(rawValue) || filePasteboardTypes.contains(rawValue) {
            return false
        }
        // Unknown to the system, or a dynamic stand-in for a legacy name: an
        // app's private note about the copy, such as a browser's source page
        // or a messaging app's reference to the message. The text does not
        // depend on it, and real content always comes with a type of its own
        // next to it.
        guard let type = UTType(rawValue), type.isDeclared else { return true }
        if type.conforms(to: .fileURL) { return false }
        // Formatted text of the same link: dropped by the rewrite, and
        // nothing is lost that the cleaned link does not say better. An RTFD
        // with an attachment would put an attachment mark in the plain text,
        // which is then no longer a link to clean.
        return type.conforms(to: .text) || type.conforms(to: .url)
            || type.conforms(to: .rtfd) || type.conforms(to: .flatRTFD)
    }
}
