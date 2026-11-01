// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import Combine
import Foundation

public enum ThemeMode: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

public enum CourierThemePreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case classicTeal
    case slate
    case midnightIndigo
    case warmPaper
    case evergreen
    case sunsetCoral
    case roseQuartz
    case oceanDeep

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classicTeal: String(localized: "Classic Teal")
        case .slate: String(localized: "Slate")
        case .midnightIndigo: String(localized: "Midnight Indigo")
        case .warmPaper: String(localized: "Warm Paper")
        case .evergreen: String(localized: "Evergreen")
        case .sunsetCoral: String(localized: "Sunset Coral")
        case .roseQuartz: String(localized: "Rose Quartz")
        case .oceanDeep: String(localized: "Ocean Deep")
        }
    }

    public var defaultAccentHex: String {
        switch self {
        case .classicTeal: "#0D9488"
        case .slate: "#475569"
        case .midnightIndigo: "#4F46E5"
        case .warmPaper: "#B45309"
        case .evergreen: "#059669"
        case .sunsetCoral: "#EA580C"
        case .roseQuartz: "#DB2777"
        case .oceanDeep: "#0284C7"
        }
    }

    public var defaultOutgoingBubbleHexLight: String {
        switch self {
        case .classicTeal: "#0D9488"
        case .slate: "#334155"
        case .midnightIndigo: "#4338CA"
        case .warmPaper: "#92400E"
        case .evergreen: "#047857"
        case .sunsetCoral: "#C2410C"
        case .roseQuartz: "#BE185D"
        case .oceanDeep: "#0369A1"
        }
    }

    public var defaultOutgoingBubbleHexDark: String {
        switch self {
        case .classicTeal: "#14B8A6"
        case .slate: "#64748B"
        case .midnightIndigo: "#6366F1"
        case .warmPaper: "#D97706"
        case .evergreen: "#10B981"
        case .sunsetCoral: "#F97316"
        case .roseQuartz: "#EC4899"
        case .oceanDeep: "#0EA5E9"
        }
    }

    public var defaultIncomingBubbleHexLight: String {
        switch self {
        case .classicTeal: "#E6F4F1"
        case .slate: "#F1F5F9"
        case .midnightIndigo: "#EEF2FF"
        case .warmPaper: "#FEF3C7"
        case .evergreen: "#ECFDF5"
        case .sunsetCoral: "#FFEDD5"
        case .roseQuartz: "#FCE7F3"
        case .oceanDeep: "#E0F2FE"
        }
    }

    public var defaultIncomingBubbleHexDark: String {
        switch self {
        case .classicTeal: "#132A28"
        case .slate: "#1E293B"
        case .midnightIndigo: "#1E1B4B"
        case .warmPaper: "#292014"
        case .evergreen: "#062E22"
        case .sunsetCoral: "#2A1810"
        case .roseQuartz: "#2D1222"
        case .oceanDeep: "#0C2538"
        }
    }

    public var canvasTintHexLight: String {
        switch self {
        case .classicTeal: "#F7FCFB"
        case .slate: "#F8FAFC"
        case .midnightIndigo: "#F8F9FF"
        case .warmPaper: "#FFFBEB"
        case .evergreen: "#F4FBF7"
        case .sunsetCoral: "#FFF7ED"
        case .roseQuartz: "#FDF2F8"
        case .oceanDeep: "#F0F9FF"
        }
    }

    public var canvasTintHexDark: String {
        switch self {
        case .classicTeal: "#0B1716"
        case .slate: "#0F172A"
        case .midnightIndigo: "#111029"
        case .warmPaper: "#1C160E"
        case .evergreen: "#041B14"
        case .sunsetCoral: "#1A0F0A"
        case .roseQuartz: "#1B0B14"
        case .oceanDeep: "#081724"
        }
    }
}

public enum CourierWallpaperPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case none
    case subtleGrid
    case topographicLines
    case softWaves
    case starfield
    case auroraGlow
    case dotMatrix
    case paperGrain

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: String(localized: "None")
        case .subtleGrid: String(localized: "Subtle Grid")
        case .topographicLines: String(localized: "Topographic Lines")
        case .softWaves: String(localized: "Soft Waves")
        case .starfield: String(localized: "Starfield")
        case .auroraGlow: String(localized: "Aurora Glow")
        case .dotMatrix: String(localized: "Dot Matrix")
        case .paperGrain: String(localized: "Paper Grain")
        }
    }

    public var subtitle: String {
        switch self {
        case .none: String(localized: "Solid conversation background")
        case .subtleGrid: String(localized: "Fine architectural rule lines")
        case .topographicLines: String(localized: "Flowing elevation contours")
        case .softWaves: String(localized: "Calm layered sine waves")
        case .starfield: String(localized: "Quiet constellation points")
        case .auroraGlow: String(localized: "Luminous northern sky ribbons")
        case .dotMatrix: String(localized: "Evenly spaced halftone dots")
        case .paperGrain: String(localized: "Warm woven stationery texture")
        }
    }
}

public enum FontSizeScale: String, CaseIterable, Codable, Sendable, Identifiable {
    case extraSmall
    case small
    case `default`
    case large
    case extraLarge

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .extraSmall: String(localized: "Extra Small (85%)")
        case .small: String(localized: "Small (92%)")
        case .default: String(localized: "Default (100%)")
        case .large: String(localized: "Large (110%)")
        case .extraLarge: String(localized: "Extra Large (125%)")
        }
    }

    public var multiplier: CGFloat {
        switch self {
        case .extraSmall: 0.85
        case .small: 0.92
        case .default: 1.0
        case .large: 1.10
        case .extraLarge: 1.25
        }
    }

    public var messageBodyPointSize: CGFloat { round(13.0 * multiplier * 2) / 2 }
    public var inboxPreviewPointSize: CGFloat { round(12.0 * multiplier * 2) / 2 }
}

public enum RedactedTextKind: String, Codable, Sendable {
    case name
    case chatTitle
    case handle
}

public struct ChatThemeOverride: Codable, Equatable, Sendable {
    public var preset: CourierThemePreset?
    public var accentColorHex: String?
    public var outgoingBubbleColorHex: String?
    public var incomingBubbleColorHex: String?
    public var wallpaper: CourierWallpaperPreset?
    public var customWallpaperPath: String?
    public var wallpaperOpacity: Double?
    public var wallpaperBlur: Bool?

    public init(
        preset: CourierThemePreset? = nil,
        accentColorHex: String? = nil,
        outgoingBubbleColorHex: String? = nil,
        incomingBubbleColorHex: String? = nil,
        wallpaper: CourierWallpaperPreset? = nil,
        customWallpaperPath: String? = nil,
        wallpaperOpacity: Double? = nil,
        wallpaperBlur: Bool? = nil
    ) {
        self.preset = preset
        self.accentColorHex = accentColorHex
        self.outgoingBubbleColorHex = outgoingBubbleColorHex
        self.incomingBubbleColorHex = incomingBubbleColorHex
        self.wallpaper = wallpaper
        self.customWallpaperPath = customWallpaperPath
        self.wallpaperOpacity = wallpaperOpacity
        self.wallpaperBlur = wallpaperBlur
    }
}

public struct ResolvedChatTheme: Equatable, Sendable {
    public let preset: CourierThemePreset
    public let accentColorHex: String
    public let outgoingBubbleHexLight: String
    public let outgoingBubbleHexDark: String
    public let incomingBubbleHexLight: String
    public let incomingBubbleHexDark: String
    public let wallpaper: CourierWallpaperPreset
    public let customWallpaperPath: String?
    public let wallpaperOpacity: Double
    public let wallpaperBlur: Bool
    public let isOverriddenForRoom: Bool

    public init(
        preset: CourierThemePreset,
        accentColorHex: String,
        outgoingBubbleHexLight: String,
        outgoingBubbleHexDark: String,
        incomingBubbleHexLight: String,
        incomingBubbleHexDark: String,
        wallpaper: CourierWallpaperPreset,
        customWallpaperPath: String?,
        wallpaperOpacity: Double,
        wallpaperBlur: Bool,
        isOverriddenForRoom: Bool
    ) {
        self.preset = preset
        self.accentColorHex = accentColorHex
        self.outgoingBubbleHexLight = outgoingBubbleHexLight
        self.outgoingBubbleHexDark = outgoingBubbleHexDark
        self.incomingBubbleHexLight = incomingBubbleHexLight
        self.incomingBubbleHexDark = incomingBubbleHexDark
        self.wallpaper = wallpaper
        self.customWallpaperPath = customWallpaperPath
        self.wallpaperOpacity = wallpaperOpacity
        self.wallpaperBlur = wallpaperBlur
        self.isOverriddenForRoom = isOverriddenForRoom
    }
}

@MainActor
public final class AppearancePreferences: ObservableObject {
    public static let zoomSteps: [Int] = [75, 80, 90, 100, 110, 125, 150]

    private enum Keys {
        static let themeMode = "courier.appearance.themeMode"
        static let themePreset = "courier.appearance.themePreset"
        static let accentColorHex = "courier.appearance.accentColorHex"
        static let outgoingBubbleColorHex = "courier.appearance.outgoingBubbleColorHex"
        static let incomingBubbleColorHex = "courier.appearance.incomingBubbleColorHex"
        static let perParticipantBubbleColors = "courier.appearance.perParticipantBubbleColors"
        static let defaultWallpaper = "courier.appearance.defaultWallpaper"
        static let customWallpaperPath = "courier.appearance.customWallpaperPath"
        static let wallpaperOpacity = "courier.appearance.wallpaperOpacity"
        static let wallpaperBlur = "courier.appearance.wallpaperBlur"
        static let chatThemes = "courier.appearance.chatThemes"
        static let fontSizeScale = "courier.appearance.fontSizeScale"
        static let zoomPercent = "courier.appearance.zoomPercent"
        static let reduceTransparency = "courier.appearance.reduceTransparency"
        static let enableMessageAnimations = "courier.appearance.enableMessageAnimations"
        static let balanceMessageText = "courier.appearance.balanceMessageText"
        static let usePointerCursor = "courier.appearance.usePointerCursor"
        static let showFeedbackWidget = "courier.appearance.showFeedbackWidget"
        static let showEmptyStateBackground = "courier.appearance.showEmptyStateBackground"
        static let showHoneycombCards = "courier.appearance.showHoneycombCards"
        static let redactNamesAndPictures = "courier.appearance.redactNamesAndPictures"
        static let selectedAppIcon = "courier.appearance.selectedAppIcon"
        static let customAppIconPath = "courier.appearance.customAppIconPath"
    }

    private let defaults: UserDefaults
    private var isInitializing = true

    public let themeFileLoader: any ThemeFileLoader
    public let appIconApplier: any AppIconApplying

    @Published public var themeMode: ThemeMode {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                themeMode = oldValue
                isInitializing = false
                return
            }
            defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        }
    }

    @Published public var themePreset: CourierThemePreset {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                themePreset = oldValue
                isInitializing = false
                return
            }
            defaults.set(themePreset.rawValue, forKey: Keys.themePreset)
        }
    }

    @Published public var accentColorHex: String? {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                accentColorHex = oldValue
                isInitializing = false
                return
            }
            defaults.set(accentColorHex, forKey: Keys.accentColorHex)
        }
    }

    @Published public var outgoingBubbleColorHex: String? {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                outgoingBubbleColorHex = oldValue
                isInitializing = false
                return
            }
            defaults.set(outgoingBubbleColorHex, forKey: Keys.outgoingBubbleColorHex)
        }
    }

    @Published public var incomingBubbleColorHex: String? {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                incomingBubbleColorHex = oldValue
                isInitializing = false
                return
            }
            defaults.set(incomingBubbleColorHex, forKey: Keys.incomingBubbleColorHex)
        }
    }

    @Published public var perParticipantBubbleColors: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                perParticipantBubbleColors = oldValue
                isInitializing = false
                return
            }
            defaults.set(perParticipantBubbleColors, forKey: Keys.perParticipantBubbleColors)
        }
    }

    @Published public var defaultWallpaper: CourierWallpaperPreset {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                defaultWallpaper = oldValue
                isInitializing = false
                return
            }
            defaults.set(defaultWallpaper.rawValue, forKey: Keys.defaultWallpaper)
        }
    }

    @Published public var customWallpaperPath: String? {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                customWallpaperPath = oldValue
                isInitializing = false
                return
            }
            defaults.set(customWallpaperPath, forKey: Keys.customWallpaperPath)
        }
    }

    @Published public var wallpaperOpacity: Double {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                wallpaperOpacity = oldValue
                isInitializing = false
                return
            }
            let clamped = min(1.0, max(0.0, wallpaperOpacity))
            if clamped != wallpaperOpacity {
                isInitializing = true
                wallpaperOpacity = clamped
                isInitializing = false
            }
            defaults.set(wallpaperOpacity, forKey: Keys.wallpaperOpacity)
        }
    }

    @Published public var wallpaperBlur: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                wallpaperBlur = oldValue
                isInitializing = false
                return
            }
            defaults.set(wallpaperBlur, forKey: Keys.wallpaperBlur)
        }
    }

    @Published public private(set) var chatThemes: [String: ChatThemeOverride]

    @Published public var fontSizeScale: FontSizeScale {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                fontSizeScale = oldValue
                isInitializing = false
                return
            }
            defaults.set(fontSizeScale.rawValue, forKey: Keys.fontSizeScale)
        }
    }

    @Published public var zoomPercent: Int {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                zoomPercent = oldValue
                isInitializing = false
                return
            }
            let clamped = min(Self.zoomSteps.last ?? 150, max(Self.zoomSteps.first ?? 75, zoomPercent))
            if clamped != zoomPercent {
                isInitializing = true
                zoomPercent = clamped
                isInitializing = false
            }
            defaults.set(zoomPercent, forKey: Keys.zoomPercent)
        }
    }

    @Published public var reduceTransparency: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                reduceTransparency = oldValue
                isInitializing = false
                return
            }
            defaults.set(reduceTransparency, forKey: Keys.reduceTransparency)
        }
    }

    @Published public var enableMessageAnimations: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                enableMessageAnimations = oldValue
                isInitializing = false
                return
            }
            defaults.set(enableMessageAnimations, forKey: Keys.enableMessageAnimations)
        }
    }

    @Published public var balanceMessageText: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                balanceMessageText = oldValue
                isInitializing = false
                return
            }
            defaults.set(balanceMessageText, forKey: Keys.balanceMessageText)
        }
    }

    @Published public var usePointerCursor: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                usePointerCursor = oldValue
                isInitializing = false
                return
            }
            defaults.set(usePointerCursor, forKey: Keys.usePointerCursor)
        }
    }

    @Published public var showFeedbackWidget: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                showFeedbackWidget = oldValue
                isInitializing = false
                return
            }
            defaults.set(showFeedbackWidget, forKey: Keys.showFeedbackWidget)
        }
    }

    @Published public var showEmptyStateBackground: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                showEmptyStateBackground = oldValue
                isInitializing = false
                return
            }
            defaults.set(showEmptyStateBackground, forKey: Keys.showEmptyStateBackground)
        }
    }

    @Published public var showHoneycombCards: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                showHoneycombCards = oldValue
                isInitializing = false
                return
            }
            defaults.set(showHoneycombCards, forKey: Keys.showHoneycombCards)
        }
    }

    @Published public var redactNamesAndPictures: Bool {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                redactNamesAndPictures = oldValue
                isInitializing = false
                return
            }
            defaults.set(redactNamesAndPictures, forKey: Keys.redactNamesAndPictures)
        }
    }

    @Published public var selectedAppIcon: CourierAppIconVariant {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                selectedAppIcon = oldValue
                isInitializing = false
                return
            }
            defaults.set(selectedAppIcon.rawValue, forKey: Keys.selectedAppIcon)
            isInitializing = true
            customAppIconPath = nil
            isInitializing = false
            defaults.removeObject(forKey: Keys.customAppIconPath)
            appIconApplier.apply(variant: selectedAppIcon)
        }
    }

    @Published public var customAppIconPath: String? {
        didSet {
            guard !isInitializing else { return }
            guard AppLockGate.shared.canPerform(.settingsChange) else {
                isInitializing = true
                customAppIconPath = oldValue
                isInitializing = false
                return
            }
            if let path = customAppIconPath {
                do {
                    try appIconApplier.applyCustomImage(at: path)
                    defaults.set(path, forKey: Keys.customAppIconPath)
                } catch {
                    isInitializing = true
                    customAppIconPath = oldValue
                    isInitializing = false
                }
            } else {
                defaults.removeObject(forKey: Keys.customAppIconPath)
                appIconApplier.apply(variant: selectedAppIcon)
            }
        }
    }

    @Published public private(set) var confettiTriggerCount: Int = 0
    @Published public private(set) var lastThemeFileNotice: String?

    public init(
        defaults: UserDefaults = .standard,
        themeFileLoader: any ThemeFileLoader = UnavailableThemeFileLoader(),
        appIconApplier: any AppIconApplying = MACAppIconApplier()
    ) {
        self.defaults = defaults
        self.themeFileLoader = themeFileLoader
        self.appIconApplier = appIconApplier

        if let raw = defaults.string(forKey: Keys.themeMode),
           let parsed = ThemeMode(rawValue: raw) {
            self.themeMode = parsed
        } else {
            self.themeMode = .system
        }

        if let raw = defaults.string(forKey: Keys.themePreset),
           let parsed = CourierThemePreset(rawValue: raw) {
            self.themePreset = parsed
        } else {
            self.themePreset = .classicTeal
        }

        self.accentColorHex = defaults.string(forKey: Keys.accentColorHex)
        self.outgoingBubbleColorHex = defaults.string(forKey: Keys.outgoingBubbleColorHex)
        self.incomingBubbleColorHex = defaults.string(forKey: Keys.incomingBubbleColorHex)
        self.perParticipantBubbleColors = defaults.object(forKey: Keys.perParticipantBubbleColors) as? Bool ?? false

        if let raw = defaults.string(forKey: Keys.defaultWallpaper),
           let parsed = CourierWallpaperPreset(rawValue: raw) {
            self.defaultWallpaper = parsed
        } else {
            self.defaultWallpaper = .none
        }

        self.customWallpaperPath = defaults.string(forKey: Keys.customWallpaperPath)
        if let savedOpacity = defaults.object(forKey: Keys.wallpaperOpacity) as? Double {
            self.wallpaperOpacity = min(1.0, max(0.0, savedOpacity))
        } else {
            self.wallpaperOpacity = 0.25
        }
        self.wallpaperBlur = defaults.object(forKey: Keys.wallpaperBlur) as? Bool ?? false

        if let data = defaults.data(forKey: Keys.chatThemes),
           let decoded = try? JSONDecoder().decode([String: ChatThemeOverride].self, from: data) {
            self.chatThemes = decoded
        } else {
            self.chatThemes = [:]
        }

        if let raw = defaults.string(forKey: Keys.fontSizeScale),
           let parsed = FontSizeScale(rawValue: raw) {
            self.fontSizeScale = parsed
        } else {
            self.fontSizeScale = .default
        }

        if let savedZoom = defaults.object(forKey: Keys.zoomPercent) as? Int {
            self.zoomPercent = min(Self.zoomSteps.last ?? 150, max(Self.zoomSteps.first ?? 75, savedZoom))
        } else {
            self.zoomPercent = 100
        }

        self.reduceTransparency = defaults.object(forKey: Keys.reduceTransparency) as? Bool ?? false
        self.enableMessageAnimations = defaults.object(forKey: Keys.enableMessageAnimations) as? Bool ?? true
        self.balanceMessageText = defaults.object(forKey: Keys.balanceMessageText) as? Bool ?? true
        self.usePointerCursor = defaults.object(forKey: Keys.usePointerCursor) as? Bool ?? false
        self.showFeedbackWidget = defaults.object(forKey: Keys.showFeedbackWidget) as? Bool ?? false
        self.showEmptyStateBackground = defaults.object(forKey: Keys.showEmptyStateBackground) as? Bool ?? true
        self.showHoneycombCards = defaults.object(forKey: Keys.showHoneycombCards) as? Bool ?? false
        self.redactNamesAndPictures = defaults.object(forKey: Keys.redactNamesAndPictures) as? Bool ?? false

        if let raw = defaults.string(forKey: Keys.selectedAppIcon),
           let parsed = CourierAppIconVariant(rawValue: raw) {
            self.selectedAppIcon = parsed
        } else {
            self.selectedAppIcon = .classicTeal
        }

        self.customAppIconPath = defaults.string(forKey: Keys.customAppIconPath)
        self.isInitializing = false
    }

    public func effectiveTheme(for roomID: String?) -> ResolvedChatTheme {
        let override = roomID.flatMap { chatThemes[$0] }
        let preset = override?.preset ?? themePreset
        let accent = override?.accentColorHex ?? accentColorHex ?? preset.defaultAccentHex
        let outgoingLight = override?.outgoingBubbleColorHex ?? outgoingBubbleColorHex ?? preset.defaultOutgoingBubbleHexLight
        let outgoingDark = override?.outgoingBubbleColorHex ?? outgoingBubbleColorHex ?? preset.defaultOutgoingBubbleHexDark
        let incomingLight = override?.incomingBubbleColorHex ?? incomingBubbleColorHex ?? preset.defaultIncomingBubbleHexLight
        let incomingDark = override?.incomingBubbleColorHex ?? incomingBubbleColorHex ?? preset.defaultIncomingBubbleHexDark
        let wallpaper = override?.wallpaper ?? defaultWallpaper
        let customPath = override?.customWallpaperPath ?? customWallpaperPath
        let opacity = override?.wallpaperOpacity ?? wallpaperOpacity
        let blur = override?.wallpaperBlur ?? wallpaperBlur

        return ResolvedChatTheme(
            preset: preset,
            accentColorHex: accent,
            outgoingBubbleHexLight: outgoingLight,
            outgoingBubbleHexDark: outgoingDark,
            incomingBubbleHexLight: incomingLight,
            incomingBubbleHexDark: incomingDark,
            wallpaper: wallpaper,
            customWallpaperPath: customPath,
            wallpaperOpacity: opacity,
            wallpaperBlur: blur,
            isOverriddenForRoom: override != nil
        )
    }

    public func setChatTheme(_ override: ChatThemeOverride, for roomID: String) {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        let trimmed = roomID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chatThemes[trimmed] = override
        persistChatThemes()
    }

    public func resetChatTheme(for roomID: String) {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        chatThemes.removeValue(forKey: roomID)
        persistChatThemes()
    }

    public func resetAllChatThemes() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        chatThemes.removeAll()
        persistChatThemes()
    }

    private func persistChatThemes() {
        if let encoded = try? JSONEncoder().encode(chatThemes) {
            defaults.set(encoded, forKey: Keys.chatThemes)
        }
    }

    /// Puts the saved app icon on the Dock; the app delegate calls it once, at launch (until then the Dock shows the
    /// bundle's icon). A custom image wins; one that can no longer be read falls back to the chosen variant. With no
    /// icon ever chosen, the bundle's icon stays.
    public func applySavedAppIcon() {
        if let path = customAppIconPath {
            do {
                try appIconApplier.applyCustomImage(at: path)
                return
            } catch {
                appIconApplier.apply(variant: selectedAppIcon)
                return
            }
        }
        if defaults.string(forKey: Keys.selectedAppIcon) != nil {
            appIconApplier.apply(variant: selectedAppIcon)
        }
    }

    /// The zoom level as a multiplier: 1.25 at 125%.
    public var zoomMultiplier: CGFloat { CGFloat(zoomPercent) / 100 }

    /// Message text size: the font size setting times the zoom level, to the half point.
    public var messageBodyPointSize: CGFloat { round(13.0 * fontSizeScale.multiplier * zoomMultiplier * 2) / 2 }

    public func zoomIn() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        if let next = Self.zoomSteps.first(where: { $0 > zoomPercent }) {
            zoomPercent = next
        } else {
            zoomPercent = Self.zoomSteps.last ?? 150
        }
    }

    public func zoomOut() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        if let prev = Self.zoomSteps.last(where: { $0 < zoomPercent }) {
            zoomPercent = prev
        } else {
            zoomPercent = Self.zoomSteps.first ?? 75
        }
    }

    public func resetZoom() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        zoomPercent = 100
    }

    public func increaseFontSize() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        let all = FontSizeScale.allCases
        if let idx = all.firstIndex(of: fontSizeScale), idx + 1 < all.count {
            fontSizeScale = all[idx + 1]
        }
    }

    public func decreaseFontSize() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        let all = FontSizeScale.allCases
        if let idx = all.firstIndex(of: fontSizeScale), idx > 0 {
            fontSizeScale = all[idx - 1]
        }
    }

    public func resetFontSize() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        fontSizeScale = .default
    }

    public func fireConfetti() {
        guard AppLockGate.shared.canPerform(.settingsChange) else { return }
        confettiTriggerCount += 1
    }

    @discardableResult
    public func attemptLoadCustomThemeFile(at url: URL) -> ThemeFileLoaderDisposition {
        guard AppLockGate.shared.canPerform(.settingsChange) else {
            return .unavailable(reason: themeFileLoader.unavailableReason)
        }
        let disposition = themeFileLoader.loadThemeFile(at: url)
        if case .unavailable(let reason) = disposition {
            lastThemeFileNotice = reason
        } else {
            lastThemeFileNotice = nil
        }
        return disposition
    }

    @discardableResult
    public func reloadCustomThemeFile() -> ThemeFileLoaderDisposition {
        guard AppLockGate.shared.canPerform(.settingsChange) else {
            return .unavailable(reason: themeFileLoader.unavailableReason)
        }
        let disposition = themeFileLoader.reload()
        if case .unavailable(let reason) = disposition {
            lastThemeFileNotice = reason
        } else {
            lastThemeFileNotice = nil
        }
        return disposition
    }

    public static func redactedText(_ original: String, kind: RedactedTextKind = .name) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch kind {
            case .name: return "Person #000"
            case .chatTitle: return "Chat #000"
            case .handle: return "@user000"
            }
        }
        // FNV-1a 32-bit deterministic hash so pseudonyms never vary across runs or platforms.
        var hash: UInt32 = 2_166_136_261
        for byte in trimmed.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        let number = Int(hash % 900) + 100
        switch kind {
        case .name:
            return "Person #\(number)"
        case .chatTitle:
            return "Chat #\(number)"
        case .handle:
            return "@user\(number)"
        }
    }

    public static func participantBubbleColorHex(for senderID: String, isDark: Bool) -> String {
        let lightPalette = [
            "#DBEAFE", "#FCE7F3", "#D1FAE5", "#FEF3C7",
            "#EDE9FE", "#FFEDD5", "#E0F2FE", "#F3E8FF",
        ]
        let darkPalette = [
            "#1E3A8A", "#500724", "#064E3B", "#451A03",
            "#2E1065", "#431407", "#0C4A6E", "#3B0764",
        ]
        var hash: UInt32 = 2_166_136_261
        for byte in senderID.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16_777_619
        }
        let index = Int(hash % UInt32(lightPalette.count))
        return isDark ? darkPalette[index] : lightPalette[index]
    }
}
