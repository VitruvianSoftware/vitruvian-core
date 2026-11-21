// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A phone number as a person reads it: "+1 949-625-4263", "+44 7974 905044", not "+19496254263".
///
/// A bridge names a chat or an account for a number it has no name for, in E.164 (a "+", then the country code and
/// the number, digits only). This groups those digits for display. It never changes what is stored or searched.
///
/// It is deliberately small: only the kinds of number that are always grouped one way. Anything else (a name, an
/// email, a number with letters or spaces already in it, a country this table doesn't know, a kind of number a
/// country groups several ways, a number of an unusual length) comes back exactly as it was, so a wrong grouping is
/// never invented.
public enum PhoneNumberFormat {
    /// `text` with its E.164 number grouped, or `text` unchanged when it isn't one this knows how to group.
    public static func display(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("+"), trimmed.count >= 8, trimmed.count <= 16 else { return text }
        let digits = trimmed.dropFirst()
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.first != "0" else { return text }
        return grouped(String(digits)) ?? text
    }

    /// The digits after the "+" as a grouped number, or nil when the country or the length isn't one known.
    private static func grouped(_ digits: String) -> String? {
        // NANP (the US, Canada and the Caribbean): +1, then a 10-digit number whose area code starts 2-9.
        if digits.hasPrefix("1") {
            let national = String(digits.dropFirst())
            guard national.count == 10, let first = national.first, first != "0", first != "1" else { return nil }
            return "+1 \(national.prefix(3))-\(national.dropFirst(3).prefix(3))-\(national.suffix(4))"
        }
        for (code, rule) in rules where digits.hasPrefix(code) {
            let national = String(digits.dropFirst(code.count))
            guard let groups = rule(national) else { return nil }
            var rest = Substring(national)
            var parts: [String] = []
            for size in groups {
                parts.append(String(rest.prefix(size)))
                rest = rest.dropFirst(size)
            }
            return "+\(code) " + parts.joined(separator: " ")
        }
        return nil
    }

    /// The group sizes for a country's national number (digits after the country code), or nil when it isn't a
    /// number that country groups one way for certain. Country calling codes are prefix-free, so the first match is
    /// the one. Where a country's numbers are grouped several ways (the UK's, Germany's, a landline's), only the
    /// kinds that are always grouped the same way are here; every other number comes back as it was, because a
    /// wrong grouping is worse than none.
    private static let rules: [(String, (String) -> [Int]?)] = [
        // United Kingdom: mobiles (7xxx xxxxxx) and London (20 xxxx xxxx). No other UK number is grouped.
        ("44", { n in
            guard n.count == 10 else { return nil }
            if n.hasPrefix("7") { return [4, 6] }
            if n.hasPrefix("20") { return [2, 4, 4] }
            return nil
        }),
        // Australia: mobiles 4xx xxx xxx; landlines 2, 3, 7 or 8 then 4 and 4.
        ("61", { n in
            guard n.count == 9 else { return nil }
            if n.hasPrefix("4") { return [3, 3, 3] }
            if let first = n.first, "2378".contains(first) { return [1, 4, 4] }
            return nil
        }),
        // France: every number is 9 digits, grouped 6 12 34 56 78.
        ("33", { n in n.count == 9 && n.first != "0" ? [1, 2, 2, 2, 2] : nil }),
        // Spain: mobiles (6xx or 7xx) in threes.
        ("34", { n in n.count == 9 && (n.hasPrefix("6") || n.hasPrefix("7")) ? [3, 3, 3] : nil }),
        // Netherlands: mobiles, 6 12345678.
        ("31", { n in n.count == 9 && n.hasPrefix("6") ? [1, 8] : nil }),
        // Mexico: Mexico City, Guadalajara and Monterrey (55, 33, 81) then 4 and 4.
        ("52", { n in n.count == 10 && ["55", "33", "81"].contains(String(n.prefix(2))) ? [2, 4, 4] : nil }),
        // Brazil: a mobile is the area code, then 9xxxx xxxx; a landline, the area code then 4 and 4.
        ("55", { n in
            let digits = Array(n)
            if n.count == 11, digits[2] == "9" { return [2, 5, 4] }
            if n.count == 10, "2345".contains(digits[2]) { return [2, 4, 4] }
            return nil
        }),
        // India: mobiles (6-9) as 98765 43210.
        ("91", { n in n.count == 10 && "6789".contains(n.first ?? "0") ? [5, 5] : nil }),
        // Japan: mobiles (70, 80, 90) as 90 1234 5678.
        ("81", { n in n.count == 10 && ["70", "80", "90"].contains(String(n.prefix(2))) ? [2, 4, 4] : nil }),
        // China: mobiles (11 digits, starting 1) as 138 0013 8000.
        ("86", { n in n.count == 11 && n.hasPrefix("1") ? [3, 4, 4] : nil }),
        // Singapore: 8 digits starting 6, 8 or 9, as 9123 4567.
        ("65", { n in n.count == 8 && "689".contains(n.first ?? "0") ? [4, 4] : nil }),
        // Ireland: mobiles (8x) as 85 123 4567.
        ("353", { n in n.count == 9 && n.hasPrefix("8") ? [2, 3, 4] : nil }),
    ]
}
