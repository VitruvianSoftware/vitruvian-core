// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A candidate offered by `:shortcode:` autocomplete or the emoji picker.
public struct EmojiCandidate: Equatable, Identifiable, Sendable {
    public var id: String             // shortcode without colons, e.g. "smile"
    public var shortcode: String      // without colons, e.g. "smile"
    public var glyph: String?         // Unicode emoji string, nil for custom emoji
    public var mediaURL: String?      // mxc:// URL for custom emoji
    public var isCustom: Bool
    public var keywords: [String]

    public init(
        id: String? = nil,
        shortcode: String,
        glyph: String? = nil,
        mediaURL: String? = nil,
        isCustom: Bool = false,
        keywords: [String] = []
    ) {
        self.id = id ?? shortcode
        self.shortcode = shortcode
        self.glyph = glyph
        self.mediaURL = mediaURL
        self.isCustom = isCustom
        self.keywords = keywords
    }
}

/// Curated `:shortcode:` catalog and trailing emoticon replacement rules.
public struct EmojiCatalog: Sendable {
    public static let shared = EmojiCatalog()

    /// Built-in Unicode emoji candidates.
    public let entries: [EmojiCandidate]

    public init(entries: [EmojiCandidate] = Self.defaultEntries) {
        self.entries = entries
    }

    /// Searches standard and custom emoji candidates for `query` (without colons), ordered by:
    /// 1. Exact shortcode match
    /// 2. Prefix shortcode match
    /// 3. Substring shortcode match
    /// 4. Keyword match
    public func search(_ query: String, custom: [EmojiCandidate] = [], limit: Int = 8) -> [EmojiCandidate] {
        guard limit > 0 else { return [] }
        let normalized = query
            .trimmingCharacters(in: CharacterSet(charactersIn: ":").union(.whitespacesAndNewlines))
            .lowercased()
        let pool = Self.deduplicated(entries + custom)
        guard !normalized.isEmpty else {
            return Array(pool.prefix(limit))
        }

        var exact: [EmojiCandidate] = []
        var prefix: [EmojiCandidate] = []
        var substring: [EmojiCandidate] = []
        var keyword: [EmojiCandidate] = []

        for candidate in pool {
            let code = candidate.shortcode.lowercased()
            if code == normalized {
                exact.append(candidate)
            } else if code.hasPrefix(normalized) {
                prefix.append(candidate)
            } else if code.contains(normalized) {
                substring.append(candidate)
            } else if candidate.keywords.contains(where: { $0.lowercased().contains(normalized) }) {
                keyword.append(candidate)
            }
        }

        return Array((exact + prefix + substring + keyword).prefix(limit))
    }

    private static func deduplicated(_ candidates: [EmojiCandidate]) -> [EmojiCandidate] {
        var seen = Set<String>()
        var result: [EmojiCandidate] = []
        result.reserveCapacity(candidates.count)
        for candidate in candidates {
            if seen.insert(candidate.shortcode.lowercased()).inserted {
                result.append(candidate)
            }
        }
        return result
    }

    // MARK: - Emoticon Replacement

    /// Returns true when `token` (e.g. `":-D"`) is a recognized ASCII emoticon.
    public static func isEmoticon(_ token: String) -> Bool {
        emoticonMap[token] != nil
    }

    private static let emoticonMap: [String: String] = [
        ":)": "🙂",
        ":-)": "🙂",
        ":D": "😃",
        ":-D": "😃",
        ";)": "😉",
        ";-)": "😉",
        ":(": "🙁",
        ":-(": "🙁",
        ":'(": "😢",
        ":P": "😛",
        ":-P": "😛",
        ":p": "😛",
        ":-p": "😛",
        "<3": "❤️",
        "</3": "💔",
        ":/": "😕",
        ":-/": "😕",
        ":O": "😮",
        ":-O": "😮",
        ":o": "😮",
        ":-o": "😮",
        "B)": "😎",
        "B-)": "😎",
        ":*": "😘",
        ":-*": "😘",
        ">_<": "😣",
        "o_O": "🤨",
        "O_o": "🤨",
    ]

    /// Inspects `text` ending with a newly typed space or newline and returns the UTF-16 `NSRange` of the trailing
    /// standalone emoticon token and its replacement glyph when applicable.
    /// Does not match inside URLs, words, or inline backtick code spans.
    public static func trailingEmoticonReplacement(in text: String) -> (range: NSRange, replacement: String)? {
        guard let lastChar = text.last, lastChar == " " || lastChar == "\n" else {
            return nil
        }
        let withoutTrailing = text.dropLast()
        guard !withoutTrailing.isEmpty else { return nil }

        // Find the start of the token immediately before the trailing space/newline.
        let tokenStart: String.Index
        if let lastWhitespace = withoutTrailing.lastIndex(where: { $0.isWhitespace || $0.isNewline }) {
            tokenStart = withoutTrailing.index(after: lastWhitespace)
        } else {
            tokenStart = withoutTrailing.startIndex
        }

        let token = String(withoutTrailing[tokenStart...])
        guard let glyph = emoticonMap[token] else {
            return nil
        }

        // Guard against inline backtick code spans (an odd number of backticks before the token).
        let prefixBeforeToken = withoutTrailing[..<tokenStart]
        let backtickCount = prefixBeforeToken.reduce(into: 0) { count, ch in
            if ch == "`" { count += 1 }
        }
        guard backtickCount % 2 == 0 else {
            return nil
        }

        let nsRange = NSRange(tokenStart..<withoutTrailing.endIndex, in: text)
        return (nsRange, glyph)
    }

    /// Inspects the token immediately before a trailing space or newline and returns the replaced text when it matches
    /// a standalone emoticon (not part of a URL or `` `code` `` span).
    public static func replaceTrailingEmoticon(in text: String) -> String? {
        guard let match = trailingEmoticonReplacement(in: text) else {
            return nil
        }
        return (text as NSString).replacingCharacters(in: match.range, with: match.replacement)
    }

    // MARK: - Built-in Shortcode Catalog

    private static func item(_ shortcode: String, _ glyph: String, _ keywords: [String] = []) -> EmojiCandidate {
        EmojiCandidate(shortcode: shortcode, glyph: glyph, keywords: keywords)
    }

    public static let defaultEntries: [EmojiCandidate] = [
        // Smileys & emotion
        item("smile", "😄", ["happy", "joy", "grin", "face"]),
        item("smiley", "😃", ["happy", "joy", "haha"]),
        item("smirk", "😏", ["smug", "sly"]),
        item("grinning", "😀", ["smile", "happy"]),
        item("grin", "😁", ["smile", "happy", "beam"]),
        item("joy", "😂", ["tears", "laugh", "lol", "haha"]),
        item("rofl", "🤣", ["laugh", "lol", "rolling"]),
        item("slightly_smiling_face", "🙂", ["smile", "happy"]),
        item("upside_down_face", "🙃", ["silly", "irony"]),
        item("wink", "😉", ["flirt", "blink"]),
        item("blush", "😊", ["smile", "happy", "warm"]),
        item("innocent", "😇", ["angel", "halo"]),
        item("Smiling_face_with_3_hearts".lowercased(), "🥰", ["love", "hearts", "adore"]),
        item("heart_eyes", "😍", ["love", "crush", "adore"]),
        item("star_struck", "🤩", ["eyes", "excited", " amazement"]),
        item("kissing_heart", "😘", ["kiss", "love", "flirt"]),
        item("kissing", "😗", ["kiss"]),
        item("relaxed", "☺️", ["blush", "warm"]),
        item("yum", "😋", ["delicious", "tongue", "food"]),
        item("stuck_out_tongue", "😛", ["playful", "silly"]),
        item("stuck_out_tongue_winking_eye", "😜", ["wink", "silly", "joke"]),
        item("zany_face", "🤪", ["goofy", "crazy", "wild"]),
        item("stuck_out_tongue_closed_eyes", "😝", ["silly", "playful"]),
        item("money_mouth_face", "🤑", ["rich", "dollar", "cash"]),
        item("hugs", "🤗", ["hug", "warm", "embrace"]),
        item("hand_over_mouth", "🤭", ["oops", "giggle"]),
        item("shushing_face", "🤫", ["quiet", "shh", "secret"]),
        item("thinking", "🤔", ["hmm", "wonder", "idea"]),
        item("zipper_mouth_face", "🤐", ["secret", "mute", "quiet"]),
        item("raised_eyebrow", "🤨", ["skeptical", "doubt"]),
        item("neutral_face", "😐", ["meh", "blank"]),
        item("expressionless", "😑", ["blank", "deadpan"]),
        item("no_mouth", "😶", ["silent", "speechless"]),
        item("unamused", "😒", ["meh", "bored", "sideeye"]),
        item("roll_eyes", "🙄", ["whatever", "eyeroll"]),
        item("grimacing", "😬", ["awkward", "yikes", "nervous"]),
        item("lying_face", "🤥", ["pinocchio", "lie"]),
        item("relieved", "😌", ["calm", "phew", "peace"]),
        item("pensive", "😔", ["sad", "thoughtful"]),
        item("sleepy", "😪", ["tired", "zzz"]),
        item("drooling_face", "🤤", ["yummy", "hungry"]),
        item("sleeping", "😴", ["zzz", "nap", "tired"]),
        item("mask", "😷", ["sick", "ill", "doctor"]),
        item("face_with_thermometer", "🤒", ["sick", "fever"]),
        item("face_with_head_bandage", "🤕", ["hurt", "injured"]),
        item("nauseated_face", "🤢", ["sick", "gross"]),
        item("vomiting_face", "🤮", ["sick", "puke"]),
        item("sneezing_face", "🤧", ["achoo", "cold"]),
        item("hot_face", "🥵", ["heat", "sweat", "spicy"]),
        item("cold_face", "🥶", ["freezing", "ice", "chill"]),
        item("woozy_face", "🥴", ["dizzy", "tipsy"]),
        item("dizzy_face", "😵", ["knocked", "shock"]),
        item("exploding_head", "🤯", ["mindblown", "shocked", "wow"]),
        item("cowboy_hat_face", "🤠", ["western", "howdy"]),
        item("partying_face", "🥳", ["celebrate", "birthday", "party"]),
        item("sunglasses", "😎", ["cool", "chill", "shades"]),
        item("nerd_face", "🤓", ["geek", "glasses", "smart"]),
        item("monocle_face", "🧐", ["inspect", "fancy"]),
        item("confused", "😕", ["puzzled", "unsure"]),
        item("worried", "😟", ["anxious", "concern"]),
        item("slightly_frowning_face", "🙁", ["sad", "frown"]),
        item("frowning_face", "☹️", ["sad", "unhappy"]),
        item("open_mouth", "😮", ["wow", "surprised"]),
        item("hushed", "😯", ["surprised", "whoa"]),
        item("astonished", "😲", ["shocked", "amazed"]),
        item("flushed", "😳", ["embarrassed", "blush"]),
        item("pleading_face", "🥺", ["puppy", "beg", "cute"]),
        item("cry", "😢", ["sad", "tear"]),
        item("sob", "😭", ["crying", "tears", "bawl"]),
        item("scream", "😱", ["scared", "shock", "omg"]),
        item("confounded", "😖", ["frustrated", "upset"]),
        item("persevere", "😣", ["struggle", "ouch"]),
        item("disappointed", "😞", ["sad", "down"]),
        item("sweat", "😓", ["hard", "stress"]),
        item("sweat_smile", "😅", ["relief", "nervous", "phew"]),
        item("weary", "😩", ["tired", "exhausted"]),
        item("tired_face", "😫", ["exhausted", "whine"]),
        item("yawning_face", "🥱", ["bored", "sleepy"]),
        item("triumph", "😤", ["huff", "proud", "steam"]),
        item("rage", "😡", ["angry", "mad", "furious"]),
        item("angry", "😠", ["mad", "annoyed"]),
        item("cursing_face", "🤬", ["swear", "angry"]),
        item("smiling_imp", "😈", ["devil", "mischief"]),
        item("skull", "💀", ["dead", "skeleton", "lol"]),
        item("poop", "💩", ["hankey", "pile"]),
        item("clown_face", "🤡", ["clown", "circus"]),
        item("ghost", "👻", ["spooky", "halloween", "boo"]),
        item("alien", "👽", ["ufo", "space"]),
        item("robot", "🤖", ["bot", "ai"]),

        // Hearts & symbols
        item("heart", "❤️", ["love", "red"]),
        item("orange_heart", "🧡", ["love", "orange"]),
        item("yellow_heart", "💛", ["love", "yellow"]),
        item("green_heart", "💚", ["love", "green"]),
        item("blue_heart", "💙", ["love", "blue"]),
        item("purple_heart", "💜", ["love", "purple"]),
        item("black_heart", "🖤", ["love", "black"]),
        item("white_heart", "🤍", ["love", "white"]),
        item("broken_heart", "💔", ["heartbreak", "sad"]),
        item("sparkling_heart", "💖", ["love", "shine"]),
        item("two_hearts", "💕", ["love", "couple"]),
        item("100", "💯", ["hundred", "perfect", "score"]),
        item("anger", "💢", ["mad", "comic"]),
        item("boom", "💥", ["explosion", "collision"]),
        item("dizzy", "💫", ["star", "sparkle"]),
        item("sweat_drops", "💦", ["water", "workout"]),
        item("dash", "💨", ["wind", "fast", "run"]),
        item("zzz", "💤", ["sleep", "snore"]),

        // Hands & people
        item("wave", "👋", ["hello", "hi", "bye"]),
        item("raised_back_of_hand", "🤚", ["stop", "hand"]),
        item("raised_hand", "✋", ["highfive", "stop"]),
        item("vulcan_salute", "🖖", ["spock", "prosper"]),
        item("ok_hand", "👌", ["okay", "nice", "perfect"]),
        item("pinched_fingers", "🤌", ["italian", "chef"]),
        item("v", "✌️", ["peace", "victory"]),
        item("crossed_fingers", "🤞", ["luck", "hope"]),
        item("love_you_gesture", "🤟", ["ily", "rock"]),
        item("metal", "🤘", ["rock", "horns"]),
        item("call_me_hand", "🤙", ["shaka", "phone"]),
        item("point_left", "👈", ["left", "direction"]),
        item("point_right", "👉", ["right", "direction"]),
        item("point_up", "👆", ["up", "direction"]),
        item("point_down", "👇", ["down", "direction"]),
        item("thumbsup", "👍", ["yes", "approve", "ok", "like", "+1"]),
        item("+1", "👍", ["thumbsup", "yes", "approve", "like"]),
        item("thumbsdown", "👎", ["no", "disapprove", "-1"]),
        item("-1", "👎", ["thumbsdown", "no", "disapprove"]),
        item("fist", "✊", ["power", "solidarity"]),
        item("punch", "👊", ["fistbump", "bro"]),
        item("clap", "👏", ["applause", "bravo", "congrats"]),
        item("raised_hands", "🙌", ["hooray", "celebrate", "yay"]),
        item("open_hands", "👐", ["hug", "hands"]),
        item("palms_up_together", "🤲", ["prayer", "offer"]),
        item("handshake", "🤝", ["deal", "agree", "meet"]),
        item("pray", "🙏", ["thanks", "please", "namaste", "hope"]),
        item("writing_hand", "✍️", ["write", "note"]),
        item("muscle", "💪", ["strong", "flex", "bicep"]),
        item("eyes", "👀", ["look", "see", "watch", "peep"]),
        item("brain", "🧠", ["smart", "think", "mind"]),
        item("shrug", "🤷", ["idk", "whatever", "dunno"]),
        item("facepalm", "🤦", ["ugh", "doh", "mistake"]),
        item("saluting_face", "🫡", ["salute", "respect", "yes sir"]),

        // Animals & nature
        item("dog", "🐶", ["puppy", "pet", "woof"]),
        item("cat", "🐱", ["kitty", "meow", "pet"]),
        item("mouse", "🐭", ["rodent", "squeak"]),
        item("rabbit", "🐰", ["bunny", "hop"]),
        item("fox_face", "🦊", ["fox", "clever"]),
        item("bear", "🐻", ["grizzly", "wildlife"]),
        item("panda_face", "🐼", ["panda", "bamboo"]),
        item("koala", "🐨", ["australia", "cute"]),
        item("tiger", "🐯", ["cat", "roar"]),
        item("lion", "🦁", ["king", "mane"]),
        item("frog", "🐸", ["toad", "ribbit"]),
        item("monkey_face", "🐵", ["monkey", "banana"]),
        item("see_no_evil", "🙈", ["monkey", "hide"]),
        item("hear_no_evil", "🙉", ["monkey", "ignore"]),
        item("speak_no_evil", "🙊", ["monkey", "oops"]),
        item("penguin", "🐧", ["bird", "ice", "linux"]),
        item("unicorn", "🦄", ["magic", "horse"]),
        item("bee", "🐝", ["honey", "buzz"]),
        item("butterfly", "🦋", ["insect", "nature"]),
        item("turtle", "🐢", ["slow", "shell"]),
        item("octopus", "🐙", ["sea", "tentacles"]),
        item("whale", "🐳", ["ocean", "sea"]),
        item("dolphin", "🐬", ["ocean", "flipper"]),
        item("fire", "🔥", ["lit", "hot", "flame"]),
        item("sparkles", "✨", ["magic", "shine", "stars"]),
        item("star", "⭐", ["favorite", "gold"]),
        item("star2", "🌟", ["glowing", "shine"]),
        item("zap", "⚡", ["lightning", "bolt", "fast"]),
        item("sunny", "☀️", ["sun", "weather", "bright"]),
        item("rainbow", "🌈", ["pride", "colorful", "weather"]),
        item("snowflake", "❄️", ["cold", "winter", "snow"]),

        // Food & drink
        item("coffee", "☕", ["cafe", "espresso", "morning"]),
        item("tea", "🍵", ["green", "matcha", "drink"]),
        item("beer", "🍺", ["Cheers", "brew", "pint"]),
        item("beers", "🍻", ["cheers", "toast", "drinks"]),
        item("clinking_glasses", "🥂", ["cheers", "champagne", "celebrate"]),
        item("wine_glass", "🍷", ["wine", "drink"]),
        item("pizza", "🍕", ["food", "slice"]),
        item("hamburger", "🍔", ["burger", "fastfood"]),
        item("fries", "🍟", ["french fries", "snack"]),
        item("taco", "🌮", ["mexican", "food"]),
        item("sushi", "🍣", ["japanese", "fish"]),
        item("ramen", "🍜", ["noodles", "soup"]),
        item("cake", "🍰", ["shortcake", "dessert", "sweet"]),
        item("birthday", "🎂", ["cake", "party", "celebrate"]),
        item("custard", "🍮", ["flan", "pudding", "dessert"]),
        item("cookie", "🍪", ["snack", "sweet", "biscuit"]),
        item("doughnut", "🍩", ["donut", "sweet"]),
        item("apple", "🍎", ["fruit", "red"]),
        item("banana", "🍌", ["fruit", "potassium"]),
        item("avocado", "🥑", ["guacamole", "green"]),

        // Celebrations, objects & status
        item("tada", "🎉", ["party", "congrats", "celebrate", "hooray"]),
        item("confetti_ball", "🎊", ["party", "celebrate"]),
        item("balloon", "🎈", ["party", "celebrate"]),
        item("gift", "🎁", ["present", "birthday"]),
        item("trophy", "🏆", ["winner", "award", "champion"]),
        item("crown", "👑", ["king", "queen", "royal"]),
        item("gem", "💎", ["diamond", "jewel"]),
        item("rocket", "🚀", ["launch", "ship", "space"]),
        item("airplane", "✈️", ["flight", "travel"]),
        item("bulb", "💡", ["idea", "light", "bright"]),
        item("bell", "🔔", ["notification", "alert", "ring"]),
        item("lock", "🔒", ["secure", "private", "closed"]),
        item("key", "🔑", ["unlock", "access", "secret"]),
        item("mag", "🔍", ["search", "find", "zoom"]),
        item("link", "🔗", ["url", "chain"]),
        item("paperclip", "📎", ["attachment", "file"]),
        item("pencil2", "✏️", ["edit", "write"]),
        item("memo", "📝", ["note", "write", "document"]),
        item("calendar", "📅", ["date", "schedule", "event"]),
        item("clock1", "🕐", ["time", "hour"]),
        item("hourglass", "⌛", ["wait", "time", "timer"]),
        item("computer", "💻", ["laptop", "code", "work"]),
        item("white_check_mark", "✅", ["check", "done", "yes", "success"]),
        item("heavy_check_mark", "✔️", ["check", "done"]),
        item("x", "❌", ["no", "cancel", "error", "cross"]),
        item("warning", "⚠️", ["alert", "caution"]),
        item("question", "❓", ["help", "ask"]),
        item("exclamation", "❗", ["important", "alert"]),
    ]
}
