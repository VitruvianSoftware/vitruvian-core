// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The tabs of the emoji picker.
public enum EmojiCategory: String, CaseIterable, Identifiable, Sendable {
    case smileys
    case hearts
    case hands
    case animals
    case food
    case objects

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smileys: String(localized: "Smileys & emotion")
        case .hearts: String(localized: "Hearts & symbols")
        case .hands: String(localized: "Hands & people")
        case .animals: String(localized: "Animals & nature")
        case .food: String(localized: "Food & drink")
        case .objects: String(localized: "Celebrations & objects")
        }
    }

    /// The SF Symbol on the category's tab.
    public var symbolName: String {
        switch self {
        case .smileys: "face.smiling"
        case .hearts: "heart"
        case .hands: "hand.raised"
        case .animals: "pawprint"
        case .food: "fork.knife"
        case .objects: "lightbulb"
        }
    }
}

/// The five skin tones (and none) a hand or person emoji can take.
public enum EmojiSkinTone: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .none: String(localized: "Default")
        case .light: String(localized: "Light")
        case .mediumLight: String(localized: "Medium light")
        case .medium: String(localized: "Medium")
        case .mediumDark: String(localized: "Medium dark")
        case .dark: String(localized: "Dark")
        }
    }

    /// The Unicode skin tone modifier (U+1F3FB to U+1F3FF); nil for `.none`.
    public var modifier: Unicode.Scalar? {
        rawValue == 0 ? nil : Unicode.Scalar(0x1F3FB + UInt32(rawValue - 1))
    }

    /// The hand shown on the tone's swatch: the same hand in each tone.
    public var swatch: String { Self.apply(self, to: "👍") }

    /// Whether `glyph` can take a skin tone: it starts with an emoji that the Unicode standard marks as a modifier
    /// base (a hand, a person). 👍 can; 😀 and ❤️ cannot.
    public static func supports(_ glyph: String) -> Bool {
        glyph.unicodeScalars.first?.properties.isEmojiModifierBase ?? false
    }

    /// `glyph` in `tone`: the tone's modifier goes right after the first emoji, where the emoji presentation selector
    /// (U+FE0F) used to be. A glyph that cannot take a tone, or one that already has one, comes back unchanged.
    public static func apply(_ tone: EmojiSkinTone, to glyph: String) -> String {
        guard let modifier = tone.modifier, supports(glyph) else { return glyph }
        var scalars = Array(glyph.unicodeScalars)
        if scalars.contains(where: { (0x1F3FB...0x1F3FF).contains($0.value) }) { return glyph }
        let base = scalars.removeFirst()
        if scalars.first?.value == 0xFE0F { scalars.removeFirst() }
        var result = String.UnicodeScalarView()
        result.append(base)
        result.append(modifier)
        result.append(contentsOf: scalars)
        return String(result)
    }
}

/// What the emoji picker remembers on this Mac: how often each emoji was chosen (for "Frequently used") and the skin
/// tone. Nothing leaves the Mac.
public final class EmojiUsageStore: @unchecked Sendable {
    public static let usageKey = "courier.emojiPicker.usage"
    public static let skinToneKey = "courier.emojiPicker.skinTone"
    /// Past this many different emoji, the least used are forgotten.
    public static let maximumRemembered = 120

    private struct Record: Codable {
        var glyph: String
        var count: Int
        var last: TimeInterval
    }

    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    /// The tone the picker applies to hands and people. Kept across launches.
    public var skinTone: EmojiSkinTone {
        get { EmojiSkinTone(rawValue: defaults.integer(forKey: Self.skinToneKey)) ?? .none }
        set { defaults.set(newValue.rawValue, forKey: Self.skinToneKey) }
    }

    /// Counts one more use of `glyph`.
    public func record(_ glyph: String) {
        guard !glyph.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var records = load()
        if let index = records.firstIndex(where: { $0.glyph == glyph }) {
            records[index].count += 1
            records[index].last = now().timeIntervalSince1970
        } else {
            records.append(Record(glyph: glyph, count: 1, last: now().timeIntervalSince1970))
        }
        if records.count > Self.maximumRemembered {
            records.sort(by: Self.isMoreUsed)
            records = Array(records.prefix(Self.maximumRemembered))
        }
        save(records)
    }

    /// The most used emoji, the most used first; of two used as often, the one used last.
    public func frequent(limit: Int = 16) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(load().sorted(by: Self.isMoreUsed).prefix(max(limit, 0)).map(\.glyph))
    }

    /// Forgets every count; the skin tone stays.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.usageKey)
    }

    private static func isMoreUsed(_ a: Record, _ b: Record) -> Bool {
        a.count != b.count ? a.count > b.count : a.last > b.last
    }

    private func load() -> [Record] {
        guard let data = defaults.data(forKey: Self.usageKey),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return [] }
        return records
    }

    private func save(_ records: [Record]) {
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.usageKey) }
    }
}

/// One emoji in the picker's grid.
public struct EmojiPickerItem: Identifiable, Equatable, Sendable {
    /// What is inserted: the emoji, in the chosen skin tone where it takes one.
    public var glyph: String
    /// The shortcode, shown as the tooltip (`thumbsup`); empty for one only known from usage.
    public var name: String
    public var id: String { glyph }
}

/// A titled run of emoji in the picker: "Frequently used", a category, or the search results.
public struct EmojiPickerSection: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var items: [EmojiPickerItem]
    /// The category a tab jumps to; nil for "Frequently used" and for search results.
    public var category: EmojiCategory?
}

/// What the emoji picker shows, worked out apart from the view so it can be tested.
public enum EmojiPickerContent {
    public static let frequentSectionID = "frequent"
    public static let resultsSectionID = "results"

    /// With a search typed: one "Results" section of what matches it. Without: "Frequently used" (once anything has
    /// been chosen), then every category in turn. The same emoji is never shown twice in a section (`thumbsup` and
    /// `+1` are both 👍), and every emoji that takes a skin tone is shown in `tone`.
    public static func sections(
        query: String,
        tone: EmojiSkinTone,
        frequent: [String],
        catalog: EmojiCatalog = .shared
    ) -> [EmojiPickerSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let found = catalog.search(trimmed, limit: 160).filter { $0.glyph != nil }
            let items = unique(found.map { item($0.glyph ?? "", name: $0.shortcode, tone: tone) })
            guard !items.isEmpty else { return [] }
            return [EmojiPickerSection(id: resultsSectionID, title: String(localized: "Results"), items: items, category: nil)]
        }
        var sections: [EmojiPickerSection] = []
        let names = Dictionary(
            catalog.entries.compactMap { entry in entry.glyph.map { ($0, entry.shortcode) } },
            uniquingKeysWith: { first, _ in first }
        )
        let used = unique(frequent.map { EmojiPickerItem(glyph: $0, name: names[$0] ?? "") })
        if !used.isEmpty {
            sections.append(EmojiPickerSection(
                id: frequentSectionID, title: String(localized: "Frequently used"), items: used, category: nil
            ))
        }
        for category in EmojiCategory.allCases {
            let items = unique(catalog.entries(in: category).compactMap { entry in
                entry.glyph.map { item($0, name: entry.shortcode, tone: tone) }
            })
            if !items.isEmpty {
                sections.append(EmojiPickerSection(id: category.id, title: category.title, items: items, category: category))
            }
        }
        return sections
    }

    private static func item(_ glyph: String, name: String, tone: EmojiSkinTone) -> EmojiPickerItem {
        EmojiPickerItem(glyph: EmojiSkinTone.apply(tone, to: glyph), name: name)
    }

    private static func unique(_ items: [EmojiPickerItem]) -> [EmojiPickerItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.glyph).inserted }
    }
}
