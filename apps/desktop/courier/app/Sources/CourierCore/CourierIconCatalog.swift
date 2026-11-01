// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum CourierIconCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case all
    case featured
    case workAndInbox
    case peopleAndPlaces
    case travelAndOutdoors
    case mediaAndObjects
    case sportsAndLeisure
    case weatherAndNature
    case symbolsAndArrows

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: String(localized: "All")
        case .featured: String(localized: "Featured")
        case .workAndInbox: String(localized: "Work & Inbox")
        case .peopleAndPlaces: String(localized: "People & Places")
        case .travelAndOutdoors: String(localized: "Travel & Outdoors")
        case .mediaAndObjects: String(localized: "Media & Objects")
        case .sportsAndLeisure: String(localized: "Sports & Leisure")
        case .weatherAndNature: String(localized: "Weather & Nature")
        case .symbolsAndArrows: String(localized: "Symbols & Arrows")
        }
    }
}

public struct CourierIconEntry: Equatable, Sendable, Identifiable {
    /// Raw inventory component name from `01-screens-and-flows.md` §22 (e.g. `"ac_unit.tsx"`, `"account_circle.tsx"`).
    public let ledgerComponent: String
    /// Native macOS SF Symbol name rendered by Courier (e.g. `"snowflake"`, `"person.crop.circle"`).
    public let sfSymbol: String
    /// Human-readable label shown in tooltips and search (e.g. `"Snowflake"`, `"Account Circle"`).
    public let title: String
    public let category: CourierIconCategory
    public let keywords: [String]

    public var id: String { ledgerComponent }

    public init(
        ledgerComponent: String,
        sfSymbol: String,
        title: String,
        category: CourierIconCategory,
        keywords: [String] = []
    ) {
        self.ledgerComponent = ledgerComponent
        self.sfSymbol = sfSymbol
        self.title = title
        self.category = category
        self.keywords = keywords
    }
}

public enum CourierIconCatalog {
    /// All 151 §22 label and space Material-Symbol-named icon rows (`ac_unit.tsx` … `wine_bar.tsx`).
    public static let labelAndSpaceIcons: [CourierIconEntry] = [
        CourierIconEntry(ledgerComponent: "ac_unit.tsx", sfSymbol: "snowflake", title: "Snowflake", category: .weatherAndNature, keywords: ["cold", "winter", "ice", "freeze"]),
        CourierIconEntry(ledgerComponent: "account_circle.tsx", sfSymbol: "person.crop.circle", title: "Account Circle", category: .peopleAndPlaces, keywords: ["user", "profile", "avatar"]),
        CourierIconEntry(ledgerComponent: "add.tsx", sfSymbol: "plus", title: "Add", category: .symbolsAndArrows, keywords: ["new", "create", "plus"]),
        CourierIconEntry(ledgerComponent: "air.tsx", sfSymbol: "wind", title: "Wind", category: .weatherAndNature, keywords: ["breeze", "air", "weather"]),
        CourierIconEntry(ledgerComponent: "archive.tsx", sfSymbol: "archivebox", title: "Archive", category: .workAndInbox, keywords: ["box", "store", "done"]),
        CourierIconEntry(ledgerComponent: "assignment.tsx", sfSymbol: "doc.plaintext", title: "Assignment", category: .workAndInbox, keywords: ["task", "clipboard", "project"]),
        CourierIconEntry(ledgerComponent: "asterisk.tsx", sfSymbol: "asterisk", title: "Asterisk", category: .symbolsAndArrows, keywords: ["star", "note", "reference"]),
        CourierIconEntry(ledgerComponent: "audio_file.tsx", sfSymbol: "waveform", title: "Audio File", category: .mediaAndObjects, keywords: ["sound", "voice", "recording"]),
        CourierIconEntry(ledgerComponent: "auto_awesome.tsx", sfSymbol: "sparkles", title: "Sparkles", category: .featured, keywords: ["magic", "ai", "stars"]),
        CourierIconEntry(ledgerComponent: "background_replace.tsx", sfSymbol: "person.and.background.dotted", title: "Background Replace", category: .mediaAndObjects, keywords: ["backdrop", "wallpaper", "portrait"]),
        CourierIconEntry(ledgerComponent: "beach_access.tsx", sfSymbol: "beach.umbrella", title: "Beach Umbrella", category: .travelAndOutdoors, keywords: ["vacation", "summer", "holiday"]),
        CourierIconEntry(ledgerComponent: "bed.tsx", sfSymbol: "bed.double", title: "Bed", category: .peopleAndPlaces, keywords: ["sleep", "hotel", "rest"]),
        CourierIconEntry(ledgerComponent: "blur_on.tsx", sfSymbol: "aqi.medium", title: "Blur", category: .mediaAndObjects, keywords: ["dots", "focus", "soft"]),
        CourierIconEntry(ledgerComponent: "bolt.tsx", sfSymbol: "bolt", title: "Bolt", category: .featured, keywords: ["lightning", "fast", "energy", "urgent"]),
        CourierIconEntry(ledgerComponent: "book_2.tsx", sfSymbol: "book", title: "Book", category: .mediaAndObjects, keywords: ["reading", "library", "novel"]),
        CourierIconEntry(ledgerComponent: "business_center.tsx", sfSymbol: "briefcase", title: "Briefcase", category: .workAndInbox, keywords: ["work", "office", "business", "job"]),
        CourierIconEntry(ledgerComponent: "cake.tsx", sfSymbol: "birthday.cake", title: "Birthday Cake", category: .sportsAndLeisure, keywords: ["party", "celebration", "dessert"]),
        CourierIconEntry(ledgerComponent: "calendar_month.tsx", sfSymbol: "calendar", title: "Calendar", category: .workAndInbox, keywords: ["date", "schedule", "event", "month"]),
        CourierIconEntry(ledgerComponent: "call.tsx", sfSymbol: "phone", title: "Phone Call", category: .workAndInbox, keywords: ["telephone", "voice", "dial"]),
        CourierIconEntry(ledgerComponent: "campaign.tsx", sfSymbol: "megaphone", title: "Announcements", category: .workAndInbox, keywords: ["megaphone", "broadcast", "news"]),
        CourierIconEntry(ledgerComponent: "casino.tsx", sfSymbol: "die.face.5", title: "Dice", category: .sportsAndLeisure, keywords: ["game", "luck", "board"]),
        CourierIconEntry(ledgerComponent: "celebration.tsx", sfSymbol: "party.popper", title: "Celebration", category: .featured, keywords: ["party", "confetti", "congrats"]),
        CourierIconEntry(ledgerComponent: "check.tsx", sfSymbol: "checkmark", title: "Check", category: .symbolsAndArrows, keywords: ["done", "complete", "yes"]),
        CourierIconEntry(ledgerComponent: "check_circle.tsx", sfSymbol: "checkmark.circle", title: "Check Circle", category: .symbolsAndArrows, keywords: ["verified", "approved", "done"]),
        CourierIconEntry(ledgerComponent: "chevron_forward.tsx", sfSymbol: "chevron.forward", title: "Chevron Forward", category: .symbolsAndArrows, keywords: ["next", "arrow", "right"]),
        CourierIconEntry(ledgerComponent: "chevron_right.tsx", sfSymbol: "chevron.right", title: "Chevron Right", category: .symbolsAndArrows, keywords: ["next", "arrow", "right"]),
        CourierIconEntry(ledgerComponent: "clear_day.tsx", sfSymbol: "sun.max", title: "Sunny Day", category: .weatherAndNature, keywords: ["sun", "bright", "daylight", "weather"]),
        CourierIconEntry(ledgerComponent: "close.tsx", sfSymbol: "xmark", title: "Close", category: .symbolsAndArrows, keywords: ["cancel", "dismiss", "delete"]),
        CourierIconEntry(ledgerComponent: "code.tsx", sfSymbol: "chevron.left.forwardslash.chevron.right", title: "Code", category: .workAndInbox, keywords: ["developer", "programming", "engineering"]),
        CourierIconEntry(ledgerComponent: "content_copy.tsx", sfSymbol: "doc.on.doc", title: "Copy", category: .workAndInbox, keywords: ["duplicate", "clipboard", "clone"]),
        CourierIconEntry(ledgerComponent: "csv.tsx", sfSymbol: "tablecells", title: "Spreadsheet", category: .workAndInbox, keywords: ["csv", "table", "data", "grid"]),
        CourierIconEntry(ledgerComponent: "deceased.tsx", sfSymbol: "leaf.arrow.triangle.circlepath", title: "Memorial", category: .weatherAndNature, keywords: ["remembrance", "flower", "tribute"]),
        CourierIconEntry(ledgerComponent: "directions_bike.tsx", sfSymbol: "bicycle", title: "Bicycle", category: .travelAndOutdoors, keywords: ["cycling", "bike", "commute"]),
        CourierIconEntry(ledgerComponent: "directions_boat.tsx", sfSymbol: "ferry", title: "Boat", category: .travelAndOutdoors, keywords: ["ship", "ferry", "water", "cruise"]),
        CourierIconEntry(ledgerComponent: "directions_car.tsx", sfSymbol: "car", title: "Car", category: .travelAndOutdoors, keywords: ["drive", "auto", "vehicle", "road"]),
        CourierIconEntry(ledgerComponent: "directions_walk.tsx", sfSymbol: "figure.walk", title: "Walking", category: .travelAndOutdoors, keywords: ["stroll", "steps", "pedestrian"]),
        CourierIconEntry(ledgerComponent: "download.tsx", sfSymbol: "arrow.down.circle", title: "Download", category: .workAndInbox, keywords: ["save", "import", "fetch"]),
        CourierIconEntry(ledgerComponent: "draft.tsx", sfSymbol: "doc", title: "Draft Document", category: .workAndInbox, keywords: ["file", "page", "note"]),
        CourierIconEntry(ledgerComponent: "edit_square.tsx", sfSymbol: "square.and.pencil", title: "Compose", category: .workAndInbox, keywords: ["write", "edit", "note"]),
        CourierIconEntry(ledgerComponent: "email.tsx", sfSymbol: "envelope", title: "Email", category: .workAndInbox, keywords: ["mail", "letter", "message"]),
        CourierIconEntry(ledgerComponent: "error_outline.tsx", sfSymbol: "exclamationmark.circle", title: "Alert Circle", category: .symbolsAndArrows, keywords: ["error", "issue", "attention"]),
        CourierIconEntry(ledgerComponent: "escalator_warning.tsx", sfSymbol: "figure.and.child.holdinghands", title: "Family & Kids", category: .peopleAndPlaces, keywords: ["parent", "child", "care"]),
        CourierIconEntry(ledgerComponent: "expand_more.tsx", sfSymbol: "chevron.down", title: "Chevron Down", category: .symbolsAndArrows, keywords: ["expand", "more", "open"]),
        CourierIconEntry(ledgerComponent: "explore.tsx", sfSymbol: "safari", title: "Compass", category: .travelAndOutdoors, keywords: ["explore", "navigate", "direction"]),
        CourierIconEntry(ledgerComponent: "eyeglasses.tsx", sfSymbol: "eyeglasses", title: "Eyeglasses", category: .mediaAndObjects, keywords: ["reading", "vision", "glasses"]),
        CourierIconEntry(ledgerComponent: "family_restroom.tsx", sfSymbol: "figure.2.and.child.holdinghands", title: "Family", category: .peopleAndPlaces, keywords: ["household", "parents", "children"]),
        CourierIconEntry(ledgerComponent: "favorite.tsx", sfSymbol: "heart", title: "Heart", category: .featured, keywords: ["favorite", "love", "like"]),
        CourierIconEntry(ledgerComponent: "filter_list.tsx", sfSymbol: "line.3.horizontal.decrease", title: "Filter", category: .workAndInbox, keywords: ["sort", "funnel", "list"]),
        CourierIconEntry(ledgerComponent: "fingerprint.tsx", sfSymbol: "touchid", title: "Fingerprint", category: .mediaAndObjects, keywords: ["security", "biometric", "identity"]),
        CourierIconEntry(ledgerComponent: "fitness_center.tsx", sfSymbol: "dumbbell", title: "Fitness", category: .sportsAndLeisure, keywords: ["gym", "workout", "weights", "exercise"]),
        CourierIconEntry(ledgerComponent: "folder_zip.tsx", sfSymbol: "doc.zipper", title: "Archive Zip", category: .workAndInbox, keywords: ["compressed", "bundle", "folder"]),
        CourierIconEntry(ledgerComponent: "footprint.tsx", sfSymbol: "shoeprints.fill", title: "Footprints", category: .travelAndOutdoors, keywords: ["steps", "trail", "tracks"]),
        CourierIconEntry(ledgerComponent: "forward.tsx", sfSymbol: "arrowshape.turn.up.right", title: "Forward", category: .symbolsAndArrows, keywords: ["share", "send", "redirect"]),
        CourierIconEntry(ledgerComponent: "function.tsx", sfSymbol: "function", title: "Function", category: .symbolsAndArrows, keywords: ["math", "formula", "code"]),
        CourierIconEntry(ledgerComponent: "group.tsx", sfSymbol: "person.2", title: "Group", category: .peopleAndPlaces, keywords: ["team", "people", "friends", "club"]),
        CourierIconEntry(ledgerComponent: "hardware.tsx", sfSymbol: "hammer", title: "Hardware & Tools", category: .mediaAndObjects, keywords: ["build", "repair", "diy", "maker"]),
        CourierIconEntry(ledgerComponent: "headset_mic.tsx", sfSymbol: "headphones", title: "Headset", category: .mediaAndObjects, keywords: ["support", "audio", "call", "gaming"]),
        CourierIconEntry(ledgerComponent: "heat.tsx", sfSymbol: "flame", title: "Flame", category: .weatherAndNature, keywords: ["heat", "fire", "hot", "trending"]),
        CourierIconEntry(ledgerComponent: "hiking.tsx", sfSymbol: "figure.hiking", title: "Hiking", category: .travelAndOutdoors, keywords: ["trail", "mountain", "trek", "outdoor"]),
        CourierIconEntry(ledgerComponent: "home.tsx", sfSymbol: "house", title: "Home", category: .featured, keywords: ["house", "family", "living"]),
        CourierIconEntry(ledgerComponent: "hourglass_bottom.tsx", sfSymbol: "hourglass", title: "Hourglass", category: .workAndInbox, keywords: ["timer", "waiting", "sand", "countdown"]),
        CourierIconEntry(ledgerComponent: "image.tsx", sfSymbol: "photo", title: "Photo", category: .mediaAndObjects, keywords: ["picture", "image", "gallery"]),
        CourierIconEntry(ledgerComponent: "inbox.tsx", sfSymbol: "tray", title: "Inbox Tray", category: .workAndInbox, keywords: ["messages", "mail", "queue"]),
        CourierIconEntry(ledgerComponent: "joystick.tsx", sfSymbol: "arcade.stick.console", title: "Arcade Stick", category: .sportsAndLeisure, keywords: ["joystick", "gaming", "retro"]),
        CourierIconEntry(ledgerComponent: "keep.tsx", sfSymbol: "pin", title: "Pin", category: .featured, keywords: ["keep", "save", "sticky"]),
        CourierIconEntry(ledgerComponent: "key.tsx", sfSymbol: "key", title: "Key", category: .mediaAndObjects, keywords: ["password", "access", "security", "lock"]),
        CourierIconEntry(ledgerComponent: "kitchen.tsx", sfSymbol: "refrigerator", title: "Kitchen", category: .peopleAndPlaces, keywords: ["food", "home", "cooking", "fridge"]),
        CourierIconEntry(ledgerComponent: "language.tsx", sfSymbol: "globe", title: "Globe", category: .travelAndOutdoors, keywords: ["world", "language", "international", "web"]),
        CourierIconEntry(ledgerComponent: "library_add.tsx", sfSymbol: "plus.rectangle.on.rectangle", title: "Add to Library", category: .mediaAndObjects, keywords: ["collection", "save", "stack"]),
        CourierIconEntry(ledgerComponent: "link.tsx", sfSymbol: "link", title: "Link", category: .symbolsAndArrows, keywords: ["url", "chain", "web", "bookmark"]),
        CourierIconEntry(ledgerComponent: "local_cafe.tsx", sfSymbol: "cup.and.saucer", title: "Cafe & Coffee", category: .peopleAndPlaces, keywords: ["coffee", "tea", "mug", "drink"]),
        CourierIconEntry(ledgerComponent: "location_city.tsx", sfSymbol: "building.2", title: "City Buildings", category: .peopleAndPlaces, keywords: ["urban", "office", "downtown", "apartments"]),
        CourierIconEntry(ledgerComponent: "looks.tsx", sfSymbol: "rainbow", title: "Rainbow", category: .weatherAndNature, keywords: ["arc", "colour", "spectrum"]),
        CourierIconEntry(ledgerComponent: "low_priority_space.tsx", sfSymbol: "arrow.down.to.line", title: "Low Priority", category: .workAndInbox, keywords: ["quiet", "later", "muted"]),
        CourierIconEntry(ledgerComponent: "map.tsx", sfSymbol: "map", title: "Map", category: .travelAndOutdoors, keywords: ["atlas", "navigation", "route", "place"]),
        CourierIconEntry(ledgerComponent: "maps_ugc.tsx", sfSymbol: "plus.bubble", title: "New Comment Bubble", category: .workAndInbox, keywords: ["feedback", "post", "place"]),
        CourierIconEntry(ledgerComponent: "mark_email_unread.tsx", sfSymbol: "envelope.badge", title: "Unread Mail", category: .workAndInbox, keywords: ["inbox", "follow-up", "unread"]),
        CourierIconEntry(ledgerComponent: "mode_comment.tsx", sfSymbol: "bubble.left", title: "Comment Bubble", category: .workAndInbox, keywords: ["chat", "message", "discussion"]),
        CourierIconEntry(ledgerComponent: "mood.tsx", sfSymbol: "face.smiling", title: "Smile", category: .featured, keywords: ["happy", "emoji", "mood", "friends"]),
        CourierIconEntry(ledgerComponent: "moon_stars.tsx", sfSymbol: "moon.stars", title: "Moon & Stars", category: .weatherAndNature, keywords: ["night", "sleep", "evening", "dream"]),
        CourierIconEntry(ledgerComponent: "moped.tsx", sfSymbol: "scooter", title: "Scooter", category: .travelAndOutdoors, keywords: ["moped", "delivery", "ride"]),
        CourierIconEntry(ledgerComponent: "more_horiz.tsx", sfSymbol: "ellipsis", title: "More Options", category: .symbolsAndArrows, keywords: ["dots", "menu", "overflow"]),
        CourierIconEntry(ledgerComponent: "motorcycle.tsx", sfSymbol: "bicycle.circle", title: "Motorbike", category: .travelAndOutdoors, keywords: ["motorcycle", "ride", "wheels"]),
        CourierIconEntry(ledgerComponent: "movie.tsx", sfSymbol: "film", title: "Movie & Film", category: .mediaAndObjects, keywords: ["cinema", "video", "cinema", "show"]),
        CourierIconEntry(ledgerComponent: "music_note.tsx", sfSymbol: "music.note", title: "Music Note", category: .mediaAndObjects, keywords: ["song", "audio", "playlist", "band"]),
        CourierIconEntry(ledgerComponent: "nature.tsx", sfSymbol: "tree", title: "Tree & Nature", category: .weatherAndNature, keywords: ["forest", "park", "outdoors", "wood"]),
        CourierIconEntry(ledgerComponent: "nest_eco_leaf.tsx", sfSymbol: "leaf", title: "Eco Leaf", category: .weatherAndNature, keywords: ["green", "plant", "nature", "sustainability"]),
        CourierIconEntry(ledgerComponent: "newspaper.tsx", sfSymbol: "newspaper", title: "Newspaper", category: .mediaAndObjects, keywords: ["news", "press", "articles", "reading"]),
        CourierIconEntry(ledgerComponent: "notifications.tsx", sfSymbol: "bell", title: "Bell", category: .featured, keywords: ["alert", "reminder", "notification"]),
        CourierIconEntry(ledgerComponent: "notifications_off.tsx", sfSymbol: "bell.slash", title: "Muted Bell", category: .workAndInbox, keywords: ["quiet", "silent", "dnd"]),
        CourierIconEntry(ledgerComponent: "pentagon.tsx", sfSymbol: "pentagon", title: "Pentagon", category: .symbolsAndArrows, keywords: ["shape", "polygon", "geometry"]),
        CourierIconEntry(ledgerComponent: "person.tsx", sfSymbol: "person", title: "Person", category: .peopleAndPlaces, keywords: ["contact", "individual", "solo"]),
        CourierIconEntry(ledgerComponent: "pets.tsx", sfSymbol: "pawprint", title: "Pets", category: .weatherAndNature, keywords: ["dog", "cat", "animal", "paw"]),
        CourierIconEntry(ledgerComponent: "photo_camera.tsx", sfSymbol: "camera", title: "Camera", category: .mediaAndObjects, keywords: ["photography", "snapshot", "lens"]),
        CourierIconEntry(ledgerComponent: "photo_library.tsx", sfSymbol: "photo.on.rectangle", title: "Photo Library", category: .mediaAndObjects, keywords: ["album", "pictures", "memories"]),
        CourierIconEntry(ledgerComponent: "podcasts.tsx", sfSymbol: "antenna.radiowaves.left.and.right", title: "Podcasts", category: .mediaAndObjects, keywords: ["radio", "show", "broadcast"]),
        CourierIconEntry(ledgerComponent: "pool.tsx", sfSymbol: "figure.pool.swim", title: "Swimming", category: .sportsAndLeisure, keywords: ["pool", "water", "laps", "dive"]),
        CourierIconEntry(ledgerComponent: "rainy.tsx", sfSymbol: "cloud.rain", title: "Rainy", category: .weatherAndNature, keywords: ["rain", "storm", "shower", "weather"]),
        CourierIconEntry(ledgerComponent: "reply.tsx", sfSymbol: "arrowshape.turn.up.left", title: "Reply", category: .symbolsAndArrows, keywords: ["answer", "respond", "back"]),
        CourierIconEntry(ledgerComponent: "restaurant.tsx", sfSymbol: "fork.knife", title: "Restaurant & Dining", category: .peopleAndPlaces, keywords: ["food", "dinner", "lunch", "meal"]),
        CourierIconEntry(ledgerComponent: "reviews.tsx", sfSymbol: "star.bubble", title: "Reviews", category: .workAndInbox, keywords: ["rating", "feedback", "testimonial"]),
        CourierIconEntry(ledgerComponent: "road.tsx", sfSymbol: "road.lanes", title: "Highway & Road", category: .travelAndOutdoors, keywords: ["trip", "street", "lane", "commute"]),
        CourierIconEntry(ledgerComponent: "rowing.tsx", sfSymbol: "figure.rower", title: "Rowing & Kayak", category: .sportsAndLeisure, keywords: ["kayak", "canoe", "paddle", "boat"]),
        CourierIconEntry(ledgerComponent: "sailing.tsx", sfSymbol: "sailboat", title: "Sailing", category: .travelAndOutdoors, keywords: ["yacht", "wind", "sea", "ocean"]),
        CourierIconEntry(ledgerComponent: "schedule.tsx", sfSymbol: "clock", title: "Clock", category: .workAndInbox, keywords: ["time", "schedule", "appointment"]),
        CourierIconEntry(ledgerComponent: "schedule_send.tsx", sfSymbol: "paperplane.circle", title: "Scheduled Send", category: .workAndInbox, keywords: ["later", "outbox", "queue"]),
        CourierIconEntry(ledgerComponent: "school.tsx", sfSymbol: "graduationcap", title: "School & Study", category: .peopleAndPlaces, keywords: ["university", "education", "class", "college"]),
        CourierIconEntry(ledgerComponent: "search.tsx", sfSymbol: "magnifyingglass", title: "Search", category: .symbolsAndArrows, keywords: ["find", "lookup", "query"]),
        CourierIconEntry(ledgerComponent: "self_improvement.tsx", sfSymbol: "figure.mind.and.body", title: "Mindfulness", category: .sportsAndLeisure, keywords: ["meditation", "yoga", "wellness", "zen"]),
        CourierIconEntry(ledgerComponent: "settings.tsx", sfSymbol: "gearshape", title: "Settings", category: .mediaAndObjects, keywords: ["gear", "preferences", "config"]),
        CourierIconEntry(ledgerComponent: "shopping_cart.tsx", sfSymbol: "cart", title: "Shopping Cart", category: .peopleAndPlaces, keywords: ["buy", "groceries", "store", "orders"]),
        CourierIconEntry(ledgerComponent: "signature.tsx", sfSymbol: "signature", title: "Signature", category: .workAndInbox, keywords: ["sign", "contract", "autograph"]),
        CourierIconEntry(ledgerComponent: "signpost.tsx", sfSymbol: "signpost.right", title: "Signpost", category: .travelAndOutdoors, keywords: ["wayfinding", "directions", "trail"]),
        CourierIconEntry(ledgerComponent: "skateboarding.tsx", sfSymbol: "figure.skateboarding", title: "Skateboarding", category: .sportsAndLeisure, keywords: ["skate", "park", "board"]),
        CourierIconEntry(ledgerComponent: "skillet_cooktop.tsx", sfSymbol: "frying.pan", title: "Cooking", category: .peopleAndPlaces, keywords: ["skillet", "recipe", "chef", "kitchen"]),
        CourierIconEntry(ledgerComponent: "sms.tsx", sfSymbol: "ellipsis.message", title: "Text Message", category: .workAndInbox, keywords: ["sms", "chat", "bubble"]),
        CourierIconEntry(ledgerComponent: "speaker.tsx", sfSymbol: "hifispeaker", title: "Speaker", category: .mediaAndObjects, keywords: ["audio", "stereo", "sound"]),
        CourierIconEntry(ledgerComponent: "speed.tsx", sfSymbol: "gauge.with.dots.needle.67percent", title: "Speedometer", category: .mediaAndObjects, keywords: ["fast", "performance", "dashboard"]),
        CourierIconEntry(ledgerComponent: "sports_basketball.tsx", sfSymbol: "basketball", title: "Basketball", category: .sportsAndLeisure, keywords: ["hoops", "court", "sport"]),
        CourierIconEntry(ledgerComponent: "sports_cricket.tsx", sfSymbol: "cricket.ball", title: "Cricket", category: .sportsAndLeisure, keywords: ["bat", "pitch", "sport"]),
        CourierIconEntry(ledgerComponent: "sports_football.tsx", sfSymbol: "football", title: "Football", category: .sportsAndLeisure, keywords: ["gridiron", "rugby", "sport"]),
        CourierIconEntry(ledgerComponent: "sports_gymnastics.tsx", sfSymbol: "figure.gymnastics", title: "Gymnastics", category: .sportsAndLeisure, keywords: ["acrobatics", "flexibility", "sport"]),
        CourierIconEntry(ledgerComponent: "sports_score.tsx", sfSymbol: "flag.checkered", title: "Checkered Flag", category: .sportsAndLeisure, keywords: ["race", "finish", "score", "goal"]),
        CourierIconEntry(ledgerComponent: "sports_soccer.tsx", sfSymbol: "soccerball", title: "Soccer", category: .sportsAndLeisure, keywords: ["football", "pitch", "goal"]),
        CourierIconEntry(ledgerComponent: "sports_tennis.tsx", sfSymbol: "tennis.racket", title: "Tennis", category: .sportsAndLeisure, keywords: ["racket", "court", "match"]),
        CourierIconEntry(ledgerComponent: "stadia_controller.tsx", sfSymbol: "gamecontroller", title: "Game Controller", category: .sportsAndLeisure, keywords: ["gaming", "console", "play"]),
        CourierIconEntry(ledgerComponent: "star.tsx", sfSymbol: "star", title: "Star", category: .featured, keywords: ["favorite", "important", "featured"]),
        CourierIconEntry(ledgerComponent: "stethoscope.tsx", sfSymbol: "stethoscope", title: "Health & Medical", category: .peopleAndPlaces, keywords: ["doctor", "clinic", "hospital", "care"]),
        CourierIconEntry(ledgerComponent: "stop.tsx", sfSymbol: "stop.circle", title: "Stop", category: .symbolsAndArrows, keywords: ["halt", "pause", "end"]),
        CourierIconEntry(ledgerComponent: "storefront.tsx", sfSymbol: "storefront", title: "Storefront", category: .peopleAndPlaces, keywords: ["shop", "market", "retail", "small business"]),
        CourierIconEntry(ledgerComponent: "stroller.tsx", sfSymbol: "stroller", title: "Stroller", category: .peopleAndPlaces, keywords: ["baby", "infant", "family", "nursery"]),
        CourierIconEntry(ledgerComponent: "stylus_pencil.tsx", sfSymbol: "pencil.tip", title: "Stylus & Drawing", category: .mediaAndObjects, keywords: ["pen", "sketch", "design", "art"]),
        CourierIconEntry(ledgerComponent: "surfing.tsx", sfSymbol: "figure.surfing", title: "Surfing", category: .sportsAndLeisure, keywords: ["waves", "ocean", "board", "beach"]),
        CourierIconEntry(ledgerComponent: "sync.tsx", sfSymbol: "arrow.triangle.2.circlepath", title: "Sync", category: .symbolsAndArrows, keywords: ["refresh", "update", "loop"]),
        CourierIconEntry(ledgerComponent: "theater_comedy.tsx", sfSymbol: "theatermasks", title: "Theater & Arts", category: .sportsAndLeisure, keywords: ["drama", "comedy", "stage", "show"]),
        CourierIconEntry(ledgerComponent: "train.tsx", sfSymbol: "tram", title: "Train & Transit", category: .travelAndOutdoors, keywords: ["rail", "subway", "commute", "station"]),
        CourierIconEntry(ledgerComponent: "translate.tsx", sfSymbol: "character.bubble", title: "Translate", category: .workAndInbox, keywords: ["language", "dictionary", "localize"]),
        CourierIconEntry(ledgerComponent: "travel.tsx", sfSymbol: "airplane", title: "Airplane & Flights", category: .travelAndOutdoors, keywords: ["flight", "trip", "airport", "journey"]),
        CourierIconEntry(ledgerComponent: "unfold_more.tsx", sfSymbol: "chevron.up.chevron.down", title: "Unfold", category: .symbolsAndArrows, keywords: ["expand", "select", "switch"]),
        CourierIconEntry(ledgerComponent: "video_file.tsx", sfSymbol: "film.stack", title: "Video File", category: .mediaAndObjects, keywords: ["clip", "recording", "media"]),
        CourierIconEntry(ledgerComponent: "videocam.tsx", sfSymbol: "video", title: "Video Call", category: .workAndInbox, keywords: ["meeting", "camera", "conference"]),
        CourierIconEntry(ledgerComponent: "view_sidebar.tsx", sfSymbol: "sidebar.left", title: "Sidebar", category: .workAndInbox, keywords: ["layout", "panel", "drawer"]),
        CourierIconEntry(ledgerComponent: "visibility.tsx", sfSymbol: "eye", title: "Visibility", category: .symbolsAndArrows, keywords: ["view", "watch", "preview", "look"]),
        CourierIconEntry(ledgerComponent: "volume_up.tsx", sfSymbol: "speaker.wave.3", title: "Volume", category: .mediaAndObjects, keywords: ["sound", "loud", "audio"]),
        CourierIconEntry(ledgerComponent: "warning.tsx", sfSymbol: "exclamationmark.triangle", title: "Warning", category: .symbolsAndArrows, keywords: ["caution", "alert", "hazard"]),
        CourierIconEntry(ledgerComponent: "watch.tsx", sfSymbol: "applewatch", title: "Watch", category: .mediaAndObjects, keywords: ["wrist", "timepiece", "wearable"]),
        CourierIconEntry(ledgerComponent: "water_bottle.tsx", sfSymbol: "waterbottle", title: "Water Bottle", category: .sportsAndLeisure, keywords: ["hydration", "drink", "flask"]),
        CourierIconEntry(ledgerComponent: "water_drop.tsx", sfSymbol: "drop", title: "Water Drop", category: .weatherAndNature, keywords: ["liquid", "aqua", "rain", "humidity"]),
        CourierIconEntry(ledgerComponent: "waves.tsx", sfSymbol: "water.waves", title: "Ocean Waves", category: .weatherAndNature, keywords: ["sea", "tide", "surf", "water"]),
        CourierIconEntry(ledgerComponent: "weekend.tsx", sfSymbol: "sofa", title: "Lounge & Weekend", category: .peopleAndPlaces, keywords: ["couch", "relax", "living room", "home"]),
        CourierIconEntry(ledgerComponent: "wine_bar.tsx", sfSymbol: "wineglass", title: "Wine Glass", category: .peopleAndPlaces, keywords: ["drinks", "bar", "toast", "dinner"]),
    ]

    /// All §22 hand-drawn / UI primitive icon rows (`OutlineCheck.tsx`, `SolidMoon.tsx`, `ConfettiIcon.tsx`, `CreateLabelNudgeIcon.tsx`, etc.).
    public static let uiPrimitiveIcons: [CourierIconEntry] = [
        CourierIconEntry(ledgerComponent: "OutlineCheck.tsx", sfSymbol: "checkmark", title: "Checkmark", category: .symbolsAndArrows, keywords: ["done", "select"]),
        CourierIconEntry(ledgerComponent: "OutlineChevronDown.tsx", sfSymbol: "chevron.down", title: "Chevron Down", category: .symbolsAndArrows, keywords: ["open", "disclosure"]),
        CourierIconEntry(ledgerComponent: "OutlineChevronDownSmall.tsx", sfSymbol: "chevron.compact.down", title: "Small Chevron Down", category: .symbolsAndArrows, keywords: ["compact", "down"]),
        CourierIconEntry(ledgerComponent: "OutlineChevronRightSmall.tsx", sfSymbol: "chevron.compact.right", title: "Small Chevron Right", category: .symbolsAndArrows, keywords: ["compact", "right"]),
        CourierIconEntry(ledgerComponent: "OutlineClip.tsx", sfSymbol: "paperclip", title: "Attachment Paperclip", category: .workAndInbox, keywords: ["attach", "file"]),
        CourierIconEntry(ledgerComponent: "OutlineClock.tsx", sfSymbol: "clock", title: "Clock", category: .workAndInbox, keywords: ["reminder", "later"]),
        CourierIconEntry(ledgerComponent: "OutlineCompose.tsx", sfSymbol: "square.and.pencil", title: "New Chat", category: .workAndInbox, keywords: ["compose", "write"]),
        CourierIconEntry(ledgerComponent: "OutlineSearch.tsx", sfSymbol: "magnifyingglass", title: "Search", category: .symbolsAndArrows, keywords: ["find"]),
        CourierIconEntry(ledgerComponent: "OutlineSidebar.tsx", sfSymbol: "sidebar.left", title: "Toggle Sidebar", category: .workAndInbox, keywords: ["panel"]),
        CourierIconEntry(ledgerComponent: "OutlineSpinner.tsx", sfSymbol: "arrow.triangle.2.circlepath", title: "Loading Spinner", category: .symbolsAndArrows, keywords: ["progress", "sync"]),
        CourierIconEntry(ledgerComponent: "OutlineTrash.tsx", sfSymbol: "trash", title: "Delete", category: .workAndInbox, keywords: ["remove", "trash"]),
        CourierIconEntry(ledgerComponent: "SolidCircleCheck.tsx", sfSymbol: "checkmark.circle.fill", title: "Selected Circle", category: .symbolsAndArrows, keywords: ["checked", "complete"]),
        CourierIconEntry(ledgerComponent: "SolidMoon.tsx", sfSymbol: "moon.fill", title: "Quiet & Incognito Moon", category: .weatherAndNature, keywords: ["incognito", "dark", "dnd"]),
        CourierIconEntry(ledgerComponent: "PlusIcon.tsx", sfSymbol: "plus.circle.fill", title: "Add Action", category: .symbolsAndArrows, keywords: ["plus", "create"]),
        CourierIconEntry(ledgerComponent: "SearchIcon.tsx", sfSymbol: "magnifyingglass.circle", title: "Search Circle", category: .symbolsAndArrows, keywords: ["query"]),
        CourierIconEntry(ledgerComponent: "ErrorCircle.tsx", sfSymbol: "exclamationmark.circle.fill", title: "Error Indicator", category: .symbolsAndArrows, keywords: ["failed", "error"]),
        CourierIconEntry(ledgerComponent: "ConfettiIcon.tsx", sfSymbol: "party.popper.fill", title: "Confetti", category: .featured, keywords: ["celebrate", "party"]),
        CourierIconEntry(ledgerComponent: "icons-custom.tsx", sfSymbol: "arrow.down.circle.fill", title: "Custom Action Icons", category: .symbolsAndArrows, keywords: ["download", "arrows"]),
        CourierIconEntry(ledgerComponent: "icons-general.tsx", sfSymbol: "bookmark.fill", title: "General Action Icons", category: .workAndInbox, keywords: ["archive", "bookmark"]),
        CourierIconEntry(ledgerComponent: "icons-toolbar.tsx", sfSymbol: "slider.horizontal.3", title: "Toolbar Icons", category: .workAndInbox, keywords: ["toolbar", "controls"]),
        CourierIconEntry(ledgerComponent: "icons-networks.tsx", sfSymbol: "network", title: "Network Badges", category: .peopleAndPlaces, keywords: ["bridges", "networks"]),
        CourierIconEntry(ledgerComponent: "icons.tsx", sfSymbol: "checkmark.seal.fill", title: "Verified & Preference Icons", category: .featured, keywords: ["verified", "badge"]),
        CourierIconEntry(ledgerComponent: "default.tsx", sfSymbol: "sparkles.rectangle.stack", title: "Assistant Avatar", category: .featured, keywords: ["assistant", "bot"]),
        CourierIconEntry(ledgerComponent: "drag_handle.tsx", sfSymbol: "line.3.horizontal", title: "Drag Handle", category: .symbolsAndArrows, keywords: ["reorder", "grab"]),
        CourierIconEntry(ledgerComponent: "drag_indicator.tsx", sfSymbol: "circle.grid.2x2", title: "Drag Grip", category: .symbolsAndArrows, keywords: ["grip", "move"]),
        CourierIconEntry(ledgerComponent: "CreateLabelNudgeIcon.tsx", sfSymbol: "tag.circle.fill", title: "Create Label Nudge", category: .featured, keywords: ["label", "space", "organize"]),
    ]

    /// Union of `LabelsModel.icons` (the quick-pick defaults) and every `sfSymbol` in `labelAndSpaceIcons`.
    public static let allowedLabelSFSymbols: Set<String> = {
        var set = Set(LabelsModel.icons)
        for entry in labelAndSpaceIcons {
            set.insert(entry.sfSymbol)
        }
        return set
    }()

    /// Filters `labelAndSpaceIcons` by category and free-text query across `title`, `ledgerComponent`, `sfSymbol`, and `keywords`.
    public static func search(query: String, category: CourierIconCategory = .all) -> [CourierIconEntry] {
        let base: [CourierIconEntry]
        if category == .all {
            base = labelAndSpaceIcons
        } else {
            base = labelAndSpaceIcons.filter { $0.category == category }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return base }

        let strippedQuery = trimmed.replacingOccurrences(of: ".tsx", with: "")
        return base.filter { entry in
            let componentBase = entry.ledgerComponent.replacingOccurrences(of: ".tsx", with: "").lowercased()
            let spacedComponent = componentBase.replacingOccurrences(of: "_", with: " ")
            if entry.title.lowercased().contains(trimmed) || entry.title.lowercased().contains(strippedQuery) {
                return true
            }
            if entry.ledgerComponent.lowercased().contains(trimmed)
                || componentBase.contains(strippedQuery)
                || spacedComponent.contains(strippedQuery)
            {
                return true
            }
            if entry.sfSymbol.lowercased().contains(trimmed) || entry.sfSymbol.lowercased().contains(strippedQuery) {
                return true
            }
            return entry.keywords.contains { kw in
                let lower = kw.lowercased()
                return lower.contains(trimmed) || lower.contains(strippedQuery)
            }
        }
    }
}
