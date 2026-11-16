// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How New Chat's A–Z **Contacts** list is ordered: people with a name first, then entries that are only a phone
/// number or a handle, with a number that is already listed under a person's name left out.
///
/// Networks hand over every number that ever messaged you, with the number itself as the display name. Sorted A–Z
/// those fill the top of the list (`+1…` sorts before any letter), so the people you know sit below dozens of numbers.
///
/// This is the one place that decides "is this name just a phone number or handle?" and which numbers are duplicates.
public enum ContactListOrdering {
    /// The contacts split for display. `named` and `other` are each A–Z; `other` has the number-only entries that
    /// no named contact already covers.
    public struct Sections: Equatable, Sendable {
        public var named: [ContactCandidate]
        public var other: [ContactCandidate]

        /// `named` then `other`: the order the list shows, and the order the arrow keys walk.
        public var ordered: [ContactCandidate] { named + other }
    }

    /// Fewest digits that make a run of digits a phone number rather than a name with a number in it ("Room 101",
    /// "Studio 54"). Local numbers without a country code are 7 digits (NANP) at the shortest.
    static let minimumPhoneDigits = 7

    /// Digits compared when matching two phone numbers. A number with a country code and the same number written
    /// without one agree on their last ten digits.
    static let phoneKeyLength = 10

    /// Whether `name` is not a name at all: empty, a phone number (E.164 `+12134476502`, or formatted
    /// `(213) 447-6502`, `+1 213-447-6502`, `tel:…`), an email address, or an `@handle`. A trailing network tag such
    /// as `(WA)` does not make a number a name. A name that merely contains digits ("Room 101") stays a name.
    public static func isNumberOrHandle(_ name: String) -> Bool {
        let core = strippedOfNetworkTag(name.trimmingCharacters(in: .whitespacesAndNewlines))
        if core.isEmpty { return true }
        if core.hasPrefix("@") { return true }
        let lower = core.lowercased()
        if lower.hasPrefix("tel:") || lower.hasPrefix("mailto:") { return true }
        if isEmailAddress(core) { return true }
        return phoneDigits(in: core) != nil
    }

    /// The key two spellings of one phone number share (`+12134476502`, `(213) 447-6502`, `+1 (213) 447-6502 (WA)`
    /// all give `2134476502`), or `nil` when `raw` is not a phone number.
    public static func phoneKey(_ raw: String) -> String? {
        var text = strippedOfNetworkTag(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.lowercased().hasPrefix("tel:") {
            text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let digits = phoneDigits(in: text) else { return nil }
        return String(digits.suffix(phoneKeyLength))
    }

    /// `candidates` split into named people and number-only entries, each A–Z, with a number-only entry dropped when
    /// a named contact has the same phone number (on any network). Nothing else is removed.
    public static func sections(_ candidates: [ContactCandidate]) -> Sections {
        var named: [ContactCandidate] = []
        var unnamed: [ContactCandidate] = []
        for candidate in candidates {
            if isNumberOrHandle(candidate.name) {
                unnamed.append(candidate)
            } else {
                named.append(candidate)
            }
        }
        var namedNumbers = Set<String>()
        for candidate in named {
            namedNumbers.formUnion(phoneKeys(of: candidate))
        }
        let other = unnamed.filter { candidate in
            namedNumbers.isDisjoint(with: phoneKeys(of: candidate))
        }
        return Sections(named: named.sorted(by: alphabetical), other: other.sorted(by: alphabetical))
    }

    // MARK: - Pieces

    /// A–Z by what the list shows as the name; ties by network, then ID, so the order never shuffles.
    private static func alphabetical(_ lhs: ContactCandidate, _ rhs: ContactCandidate) -> Bool {
        let leftName = lhs.name.isEmpty ? lhs.userID : lhs.name
        let rightName = rhs.name.isEmpty ? rhs.userID : rhs.name
        let order = leftName.localizedStandardCompare(rightName)
        if order != .orderedSame {
            return order == .orderedAscending
        }
        if lhs.network != rhs.network {
            return lhs.network < rhs.network
        }
        return lhs.userID < rhs.userID
    }

    /// Every phone number a candidate carries: the one it is named by (when it is one) and its identifiers.
    private static func phoneKeys(of candidate: ContactCandidate) -> Set<String> {
        var keys = Set<String>()
        for raw in [candidate.name] + candidate.identifiers {
            if let key = phoneKey(raw) {
                keys.insert(key)
            }
        }
        return keys
    }

    /// `text` with one trailing network tag removed: `(WA)`, `(TG)`, `(Signal)`: letters only, in parentheses, after
    /// something else. `(213)` is not a tag (digits), and neither is a string that is only a parenthesis.
    private static func strippedOfNetworkTag(_ text: String) -> String {
        guard text.hasSuffix(")"), let open = text.lastIndex(of: "(") else { return text }
        let inside = text[text.index(after: open) ..< text.index(before: text.endIndex)]
        guard !inside.isEmpty, inside.allSatisfy(\.isLetter) else { return text }
        let rest = text[text.startIndex ..< open].trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? text : rest
    }

    /// The digits of `text` when it is nothing but a phone number: digits, an optional `+` before the first digit, and the
    /// separators people type (space, `-`, `.`, parentheses); at least `minimumPhoneDigits` digits.
    private static func phoneDigits(in text: String) -> String? {
        var digits = ""
        var sawPlus = false
        for ch in text {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
            } else if ch == "+" && digits.isEmpty && !sawPlus {
                // `+1 213…`, and `(+1 213) …` where the country code sits inside the parentheses.
                sawPlus = true
            } else if " -.()\u{00A0}\u{202F}\t".contains(ch) {
                continue
            } else {
                return nil
            }
        }
        return digits.count >= minimumPhoneDigits ? digits : nil
    }

    /// `name@domain.tld`: one `@` with something either side and a dot in the domain.
    private static func isEmailAddress(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        guard !text.contains(where: \.isWhitespace) else { return false }
        return parts[1].contains(".") && !parts[1].hasPrefix(".") && !parts[1].hasSuffix(".")
    }
}
