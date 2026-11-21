// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A phone number as a person reads it: "+1 949-625-4263", "+44 7974 905044", not "+19496254263".
///
/// A bridge names a chat or an account for a number it has no name for, in E.164 (a "+", then the country code and
/// the number, digits only). This groups those digits for display. It never changes what is stored or searched.
///
/// It is deliberately small: the country codes whose numbers have one fixed length and a common way of grouping.
/// Anything else (a name, an email, a number with letters or spaces already in it, a country this table doesn't
/// know, a number of an unusual length) comes back exactly as it was, so a wrong grouping is never invented.
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
    /// length that country uses. Country calling codes are prefix-free, so the first match is the one.
    private static let rules: [(String, (String) -> [Int]?)] = [
        // United Kingdom: mobiles 7xxx xxxxxx, London 20 xxxx xxxx, the rest 10 digits as xxxx xxxxxx.
        ("44", { n in
            guard n.count == 10, n.first != "0" else { return nil }
            if n.hasPrefix("20") { return [2, 4, 4] }
            return [4, 6]
        }),
        // Australia: mobiles 4xx xxx xxx, landlines 2/3/7/8 xxxx xxxx.
        ("61", { n in
            guard n.count == 9 else { return nil }
            return n.hasPrefix("4") ? [3, 3, 3] : [1, 4, 4]
        }),
        // France: 9 digits, one then pairs: 6 12 34 56 78.
        ("33", { n in n.count == 9 && n.first != "0" ? [1, 2, 2, 2, 2] : nil }),
        // Spain: 9 digits in threes.
        ("34", { n in n.count == 9 ? [3, 3, 3] : nil }),
        // Netherlands: 9 digits, one then eight: 6 12345678.
        ("31", { n in n.count == 9 ? [1, 8] : nil }),
        // Mexico: 10 digits, two-digit area then 4 and 4: 55 1234 5678.
        ("52", { n in n.count == 10 ? [2, 4, 4] : nil }),
        // Brazil: 11 digits, two-digit area then a 9-leading mobile: 11 91234 5678.
        ("55", { n in n.count == 11 ? [2, 5, 4] : (n.count == 10 ? [2, 4, 4] : nil) }),
        // India: 10 digits, 5 and 5: 98765 43210.
        ("91", { n in n.count == 10 ? [5, 5] : nil }),
        // Japan: 10 digits, 2, 4, 4: 90 1234 5678.
        ("81", { n in n.count == 10 ? [2, 4, 4] : nil }),
        // China: 11-digit mobiles, 3, 4, 4: 138 0013 8000.
        ("86", { n in n.count == 11 ? [3, 4, 4] : nil }),
        // Vietnam: 9 digits, 3, 3, 3: 912 345 678 (a mobile written without its leading 0).
        ("84", { n in n.count == 9 ? [3, 3, 3] : nil }),
        // Singapore: 8 digits, 4 and 4.
        ("65", { n in n.count == 8 ? [4, 4] : nil }),
        // Ireland: 9 digits for a mobile: 85 123 4567.
        ("353", { n in n.count == 9 ? [2, 3, 4] : nil }),
    ]
}
