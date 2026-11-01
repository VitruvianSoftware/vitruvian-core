// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation
import XCTest

@testable import CourierCore

@MainActor
final class AppearancePreferencesTests: XCTestCase {
    @MainActor
    private final class FakeAppIconApplier: AppIconApplying {
        private(set) var appliedVariant: CourierAppIconVariant?
        private(set) var appliedCustomPath: String?
        private(set) var applyVariantCallCount = 0
        private(set) var applyCustomCallCount = 0

        func apply(variant: CourierAppIconVariant) {
            appliedVariant = variant
            appliedCustomPath = nil
            applyVariantCallCount += 1
        }

        func applyCustomImage(at path: String) throws {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let image = NSImage(contentsOfFile: trimmed),
                  image.size.width > 0,
                  image.size.height > 0
            else {
                throw AppIconApplyError.invalidImageFile(path: path)
            }
            appliedCustomPath = trimmed
            appliedVariant = nil
            applyCustomCallCount += 1
        }
    }

    private final class FakeLockedBiometricService: BiometricAuthService {
        func canEvaluateBiometricsOrWatch() -> Bool { true }
        func authenticate(reason _: String) async throws -> Bool { false }
    }

    override func tearDown() async throws {
        AppLockGate.shared.resetForTesting()
    }

    func testDefaultsMatchTheInventoryAndPersistToUserDefaults() {
        let suiteName = "test.courier.appearance.defaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let applier = FakeAppIconApplier()
        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: applier)

        // Verify out-of-the-box defaults
        XCTAssertEqual(prefs.themeMode, .system)
        XCTAssertEqual(prefs.themePreset, .classicTeal)
        XCTAssertNil(prefs.accentColorHex)
        XCTAssertNil(prefs.outgoingBubbleColorHex)
        XCTAssertNil(prefs.incomingBubbleColorHex)
        XCTAssertFalse(prefs.perParticipantBubbleColors)
        XCTAssertEqual(prefs.defaultWallpaper, .none)
        XCTAssertNil(prefs.customWallpaperPath)
        XCTAssertEqual(prefs.wallpaperOpacity, 0.25, accuracy: 0.001)
        XCTAssertFalse(prefs.wallpaperBlur)
        XCTAssertTrue(prefs.chatThemes.isEmpty)
        XCTAssertEqual(prefs.fontSizeScale, .default)
        XCTAssertEqual(prefs.zoomPercent, 100)
        XCTAssertFalse(prefs.reduceTransparency)
        XCTAssertTrue(prefs.enableMessageAnimations)
        XCTAssertTrue(prefs.balanceMessageText)
        XCTAssertFalse(prefs.usePointerCursor)
        XCTAssertFalse(prefs.showFeedbackWidget)
        XCTAssertTrue(prefs.showEmptyStateBackground)
        XCTAssertFalse(prefs.showHoneycombCards)
        XCTAssertFalse(prefs.redactNamesAndPictures)
        XCTAssertEqual(prefs.selectedAppIcon, .classicTeal)
        XCTAssertNil(prefs.customAppIconPath)
        XCTAssertEqual(prefs.confettiTriggerCount, 0)

        // Verify all enum cases have non-empty titles/labels
        for mode in ThemeMode.allCases {
            XCTAssertFalse(mode.label.isEmpty)
        }
        for preset in CourierThemePreset.allCases {
            XCTAssertFalse(preset.title.isEmpty)
            XCTAssertTrue(preset.defaultAccentHex.hasPrefix("#"))
            XCTAssertTrue(preset.defaultOutgoingBubbleHexLight.hasPrefix("#"))
            XCTAssertTrue(preset.defaultOutgoingBubbleHexDark.hasPrefix("#"))
            XCTAssertTrue(preset.defaultIncomingBubbleHexLight.hasPrefix("#"))
            XCTAssertTrue(preset.defaultIncomingBubbleHexDark.hasPrefix("#"))
            XCTAssertTrue(preset.canvasTintHexLight.hasPrefix("#"))
            XCTAssertTrue(preset.canvasTintHexDark.hasPrefix("#"))
        }
        for wp in CourierWallpaperPreset.allCases {
            XCTAssertFalse(wp.title.isEmpty)
            XCTAssertFalse(wp.subtitle.isEmpty)
        }

        // Mutate and verify persistence across a fresh AppearancePreferences(defaults:) instance
        prefs.themeMode = .dark
        prefs.themePreset = .midnightIndigo
        prefs.accentColorHex = "#4F46E5"
        prefs.outgoingBubbleColorHex = "#3730A3"
        prefs.incomingBubbleColorHex = "#1E1B4B"
        prefs.perParticipantBubbleColors = true
        prefs.defaultWallpaper = .topographicLines
        prefs.customWallpaperPath = "/tmp/wall.png"
        prefs.wallpaperOpacity = 0.6
        prefs.wallpaperBlur = true
        prefs.fontSizeScale = .large
        prefs.zoomPercent = 125
        prefs.reduceTransparency = true
        prefs.enableMessageAnimations = false
        prefs.balanceMessageText = false
        prefs.usePointerCursor = true
        prefs.showFeedbackWidget = true
        prefs.showEmptyStateBackground = false
        prefs.showHoneycombCards = true
        prefs.redactNamesAndPictures = true
        prefs.selectedAppIcon = .emeraldForest

        let reloadedApplier = FakeAppIconApplier()
        let reloaded = AppearancePreferences(defaults: defaults, appIconApplier: reloadedApplier)
        XCTAssertEqual(reloaded.themeMode, .dark)
        XCTAssertEqual(reloaded.themePreset, .midnightIndigo)
        XCTAssertEqual(reloaded.accentColorHex, "#4F46E5")
        XCTAssertEqual(reloaded.outgoingBubbleColorHex, "#3730A3")
        XCTAssertEqual(reloaded.incomingBubbleColorHex, "#1E1B4B")
        XCTAssertTrue(reloaded.perParticipantBubbleColors)
        XCTAssertEqual(reloaded.defaultWallpaper, .topographicLines)
        XCTAssertEqual(reloaded.customWallpaperPath, "/tmp/wall.png")
        XCTAssertEqual(reloaded.wallpaperOpacity, 0.6, accuracy: 0.001)
        XCTAssertTrue(reloaded.wallpaperBlur)
        XCTAssertEqual(reloaded.fontSizeScale, .large)
        XCTAssertEqual(reloaded.zoomPercent, 125)
        XCTAssertTrue(reloaded.reduceTransparency)
        XCTAssertFalse(reloaded.enableMessageAnimations)
        XCTAssertFalse(reloaded.balanceMessageText)
        XCTAssertTrue(reloaded.usePointerCursor)
        XCTAssertTrue(reloaded.showFeedbackWidget)
        XCTAssertFalse(reloaded.showEmptyStateBackground)
        XCTAssertTrue(reloaded.showHoneycombCards)
        XCTAssertTrue(reloaded.redactNamesAndPictures)
        XCTAssertEqual(reloaded.selectedAppIcon, .emeraldForest)
    }

    func testPerChatThemeOverrideMergesAndResetsCleanly() {
        let suiteName = "test.courier.appearance.chattheme.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: FakeAppIconApplier())
        prefs.themePreset = .classicTeal
        prefs.defaultWallpaper = .subtleGrid
        prefs.wallpaperOpacity = 0.3
        prefs.wallpaperBlur = false

        let overrideRoom1 = ChatThemeOverride(
            preset: .sunsetCoral,
            accentColorHex: "#EA580C",
            outgoingBubbleColorHex: "#F97316",
            incomingBubbleColorHex: "#FED7AA",
            wallpaper: .starfield,
            customWallpaperPath: "/tmp/room1-stars.png",
            wallpaperOpacity: 0.75,
            wallpaperBlur: true
        )
        prefs.setChatTheme(overrideRoom1, for: "!room1:courier.local")

        let resolvedRoom1 = prefs.effectiveTheme(for: "!room1:courier.local")
        XCTAssertTrue(resolvedRoom1.isOverriddenForRoom)
        XCTAssertEqual(resolvedRoom1.preset, .sunsetCoral)
        XCTAssertEqual(resolvedRoom1.accentColorHex, "#EA580C")
        XCTAssertEqual(resolvedRoom1.outgoingBubbleHexLight, "#F97316")
        XCTAssertEqual(resolvedRoom1.outgoingBubbleHexDark, "#F97316")
        XCTAssertEqual(resolvedRoom1.incomingBubbleHexLight, "#FED7AA")
        XCTAssertEqual(resolvedRoom1.incomingBubbleHexDark, "#FED7AA")
        XCTAssertEqual(resolvedRoom1.wallpaper, .starfield)
        XCTAssertEqual(resolvedRoom1.customWallpaperPath, "/tmp/room1-stars.png")
        XCTAssertEqual(resolvedRoom1.wallpaperOpacity, 0.75, accuracy: 0.001)
        XCTAssertTrue(resolvedRoom1.wallpaperBlur)

        // Room 2 has no override and falls back to global defaults
        let resolvedRoom2 = prefs.effectiveTheme(for: "!room2:courier.local")
        XCTAssertFalse(resolvedRoom2.isOverriddenForRoom)
        XCTAssertEqual(resolvedRoom2.preset, .classicTeal)
        XCTAssertEqual(resolvedRoom2.accentColorHex, CourierThemePreset.classicTeal.defaultAccentHex)
        XCTAssertEqual(resolvedRoom2.wallpaper, .subtleGrid)
        XCTAssertNil(resolvedRoom2.customWallpaperPath)
        XCTAssertEqual(resolvedRoom2.wallpaperOpacity, 0.3, accuracy: 0.001)
        XCTAssertFalse(resolvedRoom2.wallpaperBlur)

        // Persists across reload
        let reloaded = AppearancePreferences(defaults: defaults, appIconApplier: FakeAppIconApplier())
        XCTAssertEqual(reloaded.chatThemes["!room1:courier.local"], overrideRoom1)

        // Reset single room
        prefs.setChatTheme(ChatThemeOverride(preset: .oceanDeep), for: "!room2:courier.local")
        XCTAssertTrue(prefs.effectiveTheme(for: "!room2:courier.local").isOverriddenForRoom)
        prefs.resetChatTheme(for: "!room1:courier.local")
        XCTAssertFalse(prefs.effectiveTheme(for: "!room1:courier.local").isOverriddenForRoom)
        XCTAssertTrue(prefs.effectiveTheme(for: "!room2:courier.local").isOverriddenForRoom)

        // Reset all chat themes
        prefs.resetAllChatThemes()
        XCTAssertTrue(prefs.chatThemes.isEmpty)
        XCTAssertFalse(prefs.effectiveTheme(for: "!room2:courier.local").isOverriddenForRoom)
    }

    func testZoomAndFontSizeSteppingClampsToBounds() {
        let suiteName = "test.courier.appearance.stepping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: FakeAppIconApplier())
        XCTAssertEqual(AppearancePreferences.zoomSteps, [75, 80, 90, 100, 110, 125, 150])
        XCTAssertEqual(prefs.zoomPercent, 100)

        prefs.zoomIn()
        XCTAssertEqual(prefs.zoomPercent, 110)
        prefs.zoomIn()
        XCTAssertEqual(prefs.zoomPercent, 125)
        prefs.zoomIn()
        XCTAssertEqual(prefs.zoomPercent, 150)
        // Clamps at upper bound 150
        prefs.zoomIn()
        XCTAssertEqual(prefs.zoomPercent, 150)

        prefs.resetZoom()
        XCTAssertEqual(prefs.zoomPercent, 100)

        prefs.zoomOut()
        XCTAssertEqual(prefs.zoomPercent, 90)
        prefs.zoomOut()
        XCTAssertEqual(prefs.zoomPercent, 80)
        prefs.zoomOut()
        XCTAssertEqual(prefs.zoomPercent, 75)
        // Clamps at lower bound 75
        prefs.zoomOut()
        XCTAssertEqual(prefs.zoomPercent, 75)

        // Font size stepping across FontSizeScale.allCases
        XCTAssertEqual(prefs.fontSizeScale, .default)
        XCTAssertEqual(FontSizeScale.extraSmall.multiplier, 0.85, accuracy: 0.001)
        XCTAssertEqual(FontSizeScale.small.multiplier, 0.92, accuracy: 0.001)
        XCTAssertEqual(FontSizeScale.default.multiplier, 1.0, accuracy: 0.001)
        XCTAssertEqual(FontSizeScale.large.multiplier, 1.10, accuracy: 0.001)
        XCTAssertEqual(FontSizeScale.extraLarge.multiplier, 1.25, accuracy: 0.001)

        prefs.increaseFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .large)
        prefs.increaseFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .extraLarge)
        prefs.increaseFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .extraLarge)

        prefs.resetFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .default)

        prefs.decreaseFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .small)
        prefs.decreaseFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .extraSmall)
        prefs.decreaseFontSize()
        XCTAssertEqual(prefs.fontSizeScale, .extraSmall)
    }

    /// A saved icon is put on the Dock at launch: a chosen variant, or a custom image (falling back to the variant
    /// when the image can no longer be read). With nothing saved, the bundle's icon is left alone.
    func testSavedAppIconIsAppliedAtLaunch() throws {
        let suiteName = "test.courier.appearance.launchicon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fresh = FakeAppIconApplier()
        AppearancePreferences(defaults: defaults, appIconApplier: fresh).applySavedAppIcon()
        XCTAssertEqual(fresh.applyVariantCallCount + fresh.applyCustomCallCount, 0, "nothing saved, nothing applied")

        AppearancePreferences(defaults: defaults, appIconApplier: FakeAppIconApplier()).selectedAppIcon = .violetPulse
        let relaunched = FakeAppIconApplier()
        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: relaunched)
        XCTAssertNil(relaunched.appliedVariant, "loading the preferences applies nothing by itself")
        prefs.applySavedAppIcon()
        XCTAssertEqual(relaunched.appliedVariant, .violetPulse)

        let iconURL = FileManager.default.temporaryDirectory.appendingPathComponent("launch-icon-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: iconURL) }
        let image = AppIconRenderer.renderIcon(variant: .copperCraft, size: 64)
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: iconURL)
        prefs.customAppIconPath = iconURL.path
        let withCustom = FakeAppIconApplier()
        AppearancePreferences(defaults: defaults, appIconApplier: withCustom).applySavedAppIcon()
        XCTAssertEqual(withCustom.appliedCustomPath, iconURL.path)

        try FileManager.default.removeItem(at: iconURL)
        let missingCustom = FakeAppIconApplier()
        AppearancePreferences(defaults: defaults, appIconApplier: missingCustom).applySavedAppIcon()
        XCTAssertNil(missingCustom.appliedCustomPath)
        XCTAssertEqual(missingCustom.appliedVariant, .violetPulse, "an unreadable custom image falls back to the variant")
    }

    /// The zoom level scales message text with the font size setting: 125% is a quarter larger.
    func testZoomScalesMessageText() {
        let suiteName = "test.courier.appearance.zoom.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: FakeAppIconApplier())
        XCTAssertEqual(prefs.messageBodyPointSize, 13)
        prefs.zoomPercent = 125
        XCTAssertEqual(prefs.zoomMultiplier, 1.25)
        XCTAssertEqual(prefs.messageBodyPointSize, 16.5)
        prefs.fontSizeScale = .large
        XCTAssertEqual(prefs.messageBodyPointSize, 18)
        prefs.resetZoom()
        XCTAssertEqual(prefs.messageBodyPointSize, 14.5)
    }

    func testAppIconRendererProducesNonEmptyBitmapForEveryVariantAndAppliesToDock() throws {
        let suiteName = "test.courier.appearance.appicon.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(CourierAppIconVariant.allCases.count, 8)
        var cornerColors: Set<String> = []

        for variant in CourierAppIconVariant.allCases {
            XCTAssertFalse(variant.title.isEmpty)
            XCTAssertFalse(variant.subtitle.isEmpty)

            let image = AppIconRenderer.renderIcon(variant: variant, size: 128)
            XCTAssertEqual(image.size.width, 128)
            XCTAssertEqual(image.size.height, 128)

            var rect = CGRect(x: 0, y: 0, width: 128, height: 128)
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
            XCTAssertEqual(cgImage.width, 128)
            XCTAssertEqual(cgImage.height, 128)

            let space = CGColorSpaceCreateDeviceRGB()
            var pixelData = [UInt8](repeating: 0, count: 128 * 128 * 4)
            let ctx = try XCTUnwrap(
                CGContext(
                    data: &pixelData,
                    width: 128,
                    height: 128,
                    bitsPerComponent: 8,
                    bytesPerRow: 128 * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            )
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 128, height: 128))

            // Center pixel (64, 64) must be opaque
            let centerIndex = (64 * 128 + 64) * 4
            XCTAssertGreaterThan(pixelData[centerIndex + 3], 200, "Center pixel of \(variant) must be opaque")

            // Tile sample pixel (28, 28) is inside the rounded squircle background and differs across variants
            let tileIndex = (28 * 128 + 28) * 4
            let sampleKey = "\(pixelData[tileIndex])-\(pixelData[tileIndex + 1])-\(pixelData[tileIndex + 2])"
            cornerColors.insert(sampleKey)
        }

        XCTAssertEqual(
            cornerColors.count,
            CourierAppIconVariant.allCases.count,
            "Every CourierAppIconVariant must render a distinct tile palette"
        )

        let applier = FakeAppIconApplier()
        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: applier)
        prefs.selectedAppIcon = .violetPulse
        XCTAssertEqual(applier.appliedVariant, .violetPulse)

        // Rejects non-image or missing custom icon path
        XCTAssertThrowsError(try applier.applyCustomImage(at: "/nonexistent/not-an-icon.txt"))
        XCTAssertEqual(applier.appliedVariant, .violetPulse)
        XCTAssertNil(applier.appliedCustomPath)
    }

    func testRedactNamesAndPicturesProducesDeterministicPseudonymsAndAppLockBlocksMutations() {
        let suiteName = "test.courier.appearance.redact.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let name1 = AppearancePreferences.redactedText("Alice Nguyen", kind: .name)
        let name1Again = AppearancePreferences.redactedText("Alice Nguyen", kind: .name)
        let name2 = AppearancePreferences.redactedText("Bob Smith", kind: .name)
        let chat1 = AppearancePreferences.redactedText("Alice Nguyen & Bob", kind: .chatTitle)

        XCTAssertEqual(name1, name1Again, "Pseudonym must be deterministic for the same input")
        XCTAssertNotEqual(name1, name2, "Distinct names should produce distinct pseudonyms")
        XCTAssertTrue(name1.hasPrefix("Person #"), "Expected Person #… format, got \(name1)")
        XCTAssertTrue(chat1.hasPrefix("Chat #"), "Expected Chat #… format, got \(chat1)")
        XCTAssertFalse(name1.localizedCaseInsensitiveContains("Alice"))
        XCTAssertFalse(name1.localizedCaseInsensitiveContains("Nguyen"))
        XCTAssertFalse(chat1.localizedCaseInsensitiveContains("Alice"))

        // Participant bubble colours are deterministic hex strings
        let hexLight = AppearancePreferences.participantBubbleColorHex(for: "@alice:courier.local", isDark: false)
        let hexDark = AppearancePreferences.participantBubbleColorHex(for: "@alice:courier.local", isDark: true)
        XCTAssertTrue(hexLight.hasPrefix("#"))
        XCTAssertTrue(hexDark.hasPrefix("#"))
        XCTAssertNotEqual(hexLight, hexDark)

        // Confetti and ThemeFileLoader
        let applier = FakeAppIconApplier()
        let prefs = AppearancePreferences(defaults: defaults, appIconApplier: applier)
        prefs.fireConfetti()
        XCTAssertEqual(prefs.confettiTriggerCount, 1)
        let loadDisp = prefs.attemptLoadCustomThemeFile(at: URL(fileURLWithPath: "/tmp/theme.css"))
        XCTAssertEqual(loadDisp, .unavailable(reason: prefs.themeFileLoader.unavailableReason))
        XCTAssertEqual(prefs.lastThemeFileNotice, prefs.themeFileLoader.unavailableReason)

        // Lock Courier via SystemLifecycleModel and verify all mutations are blocked
        let lifecycle = SystemLifecycleModel(
            loginItemService: StubLoginItemService(),
            biometricService: FakeLockedBiometricService(),
            defaults: defaults
        )
        lifecycle.lockApp()
        XCTAssertTrue(AppLockGate.shared.isLocked)

        prefs.themeMode = .dark
        prefs.themePreset = .oceanDeep
        prefs.defaultWallpaper = .auroraGlow
        prefs.fontSizeScale = .extraLarge
        prefs.zoomIn()
        prefs.redactNamesAndPictures = true
        prefs.selectedAppIcon = .copperCraft
        prefs.setChatTheme(ChatThemeOverride(preset: .roseQuartz), for: "!locked:courier.local")
        prefs.fireConfetti()

        XCTAssertEqual(prefs.themeMode, .system)
        XCTAssertEqual(prefs.themePreset, .classicTeal)
        XCTAssertEqual(prefs.defaultWallpaper, .none)
        XCTAssertEqual(prefs.fontSizeScale, .default)
        XCTAssertEqual(prefs.zoomPercent, 100)
        XCTAssertFalse(prefs.redactNamesAndPictures)
        XCTAssertEqual(prefs.selectedAppIcon, .classicTeal)
        XCTAssertNil(prefs.chatThemes["!locked:courier.local"])
        XCTAssertEqual(prefs.confettiTriggerCount, 1)
    }
}

private struct StubLoginItemService: LoginItemService {
    func status() -> LoginItemRegistrationStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}
