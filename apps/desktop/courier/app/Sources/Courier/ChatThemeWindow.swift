// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CourierCore
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    public init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

/// `ChatThemeWindow.tsx` — per-chat theme, bubble colour, and wallpaper editor sheet/window.
public struct ChatThemeWindow: View {
    public let roomID: String
    public let chatTitle: String
    @ObservedObject public var appearance: AppearancePreferences
    public var onDismiss: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let bubblePaletteSwatches: [String] = [
        "#0D9488", "#4F46E5", "#0284C7", "#059669",
        "#EA580C", "#DB2777", "#B45309", "#475569",
    ]

    public init(
        roomID: String,
        chatTitle: String,
        appearance: AppearancePreferences,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.roomID = roomID
        self.chatTitle = chatTitle
        self.appearance = appearance
        self.onDismiss = onDismiss
    }

    private var currentOverride: ChatThemeOverride {
        appearance.chatThemes[roomID] ?? ChatThemeOverride()
    }

    private var resolved: ResolvedChatTheme {
        appearance.effectiveTheme(for: roomID)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Chat Theme"))
                        .font(.title3.weight(.semibold))
                    Text(chatTitle.isEmpty ? String(localized: "Selected chat") : chatTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if resolved.isOverriddenForRoom {
                    Text(String(localized: "Custom for this chat"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                } else {
                    Text(String(localized: "Using default theme"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            livePreviewCard

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Colour Preset"))
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 8)], spacing: 8) {
                            ForEach(CourierThemePreset.allCases) { preset in
                                presetButton(preset)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Outgoing Bubble Colour"))
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            ForEach(bubblePaletteSwatches, id: \.self) { hex in
                                swatchCircle(
                                    hex: hex,
                                    isSelected: currentOverride.outgoingBubbleColorHex == hex
                                ) {
                                    updateOverride { $0.outgoingBubbleColorHex = hex }
                                }
                            }
                            if currentOverride.outgoingBubbleColorHex != nil {
                                Button(String(localized: "Default")) {
                                    updateOverride { $0.outgoingBubbleColorHex = nil }
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Wallpaper"))
                            .font(.subheadline.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 150), spacing: 8)], spacing: 8) {
                            ForEach(CourierWallpaperPreset.allCases) { wp in
                                wallpaperButton(wp)
                            }
                        }
                    }

                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Text(String(localized: "Wallpaper Opacity"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { resolved.wallpaperOpacity },
                                    set: { val in updateOverride { $0.wallpaperOpacity = val } }
                                ),
                                in: 0.05 ... 0.85
                            )
                            .frame(width: 140)
                            Text("\(Int((resolved.wallpaperOpacity * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }

                        Toggle(
                            String(localized: "Soft Blur"),
                            isOn: Binding(
                                get: { resolved.wallpaperBlur },
                                set: { val in updateOverride { $0.wallpaperBlur = val } }
                            )
                        )
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                if resolved.isOverriddenForRoom {
                    Button(String(localized: "Reset to Default Theme")) {
                        appearance.resetChatTheme(for: roomID)
                    }
                }
                Spacer(minLength: 8)
                Button(String(localized: "Done")) {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 520)
    }

    private var livePreviewCard: some View {
        let isDark = colorScheme == .dark
        let outgoingHex = isDark ? resolved.outgoingBubbleHexDark : resolved.outgoingBubbleHexLight
        let incomingHex = isDark ? resolved.incomingBubbleHexDark : resolved.incomingBubbleHexLight
        let canvasHex = isDark ? resolved.preset.canvasTintHexDark : resolved.preset.canvasTintHexLight
        let outgoingColor = Color(hex: outgoingHex) ?? Color.accentColor
        let incomingColor = Color(hex: incomingHex) ?? Color.primary.opacity(0.10)
        let canvasColor = Color(hex: canvasHex) ?? Color(nsColor: .textBackgroundColor)

        return ZStack {
            canvasColor
            ChatWallpaperCanvasView(
                preset: resolved.wallpaper,
                customImagePath: resolved.customWallpaperPath,
                opacity: resolved.wallpaperOpacity,
                blur: resolved.wallpaperBlur,
                reduceTransparency: appearance.reduceTransparency
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "Are we still on for coffee at 10?"))
                        .font(.system(size: appearance.fontSizeScale.messageBodyPointSize))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14).fill(incomingColor))
                    Spacer(minLength: 40)
                }
                HStack {
                    Spacer(minLength: 40)
                    Text(String(localized: "Yes! Bringing the trail maps too."))
                        .font(.system(size: appearance.fontSizeScale.messageBodyPointSize))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14).fill(outgoingColor))
                }
            }
            .padding(14)
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func presetButton(_ preset: CourierThemePreset) -> some View {
        let isSelected = resolved.preset == preset
        let accent = Color(hex: preset.defaultAccentHex) ?? .accentColor
        return Button {
            updateOverride { $0.preset = preset }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 14, height: 14)
                Text(preset.title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? accent : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func wallpaperButton(_ wp: CourierWallpaperPreset) -> some View {
        let isSelected = resolved.wallpaper == wp
        return Button {
            updateOverride { $0.wallpaper = wp }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(wp.title)
                        .font(.caption.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(wp.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func swatchCircle(hex: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let color = Color(hex: hex) ?? .accentColor
        return Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .help(hex)
    }

    private func updateOverride(_ mutate: (inout ChatThemeOverride) -> Void) {
        var override = currentOverride
        mutate(&override)
        appearance.setChatTheme(override, for: roomID)
    }
}

/// `ChatThemeBrowserWindow.tsx` — standalone gallery browser of all 8 Courier theme presets and 8 procedural wallpapers
/// with a live conversation preview, "Use as Default Theme", and optional "Apply to <Current Chat>".
public struct ChatThemeBrowserWindow: View {
    @ObservedObject public var appearance: AppearancePreferences
    public var activeRoomID: String? = nil
    public var activeChatTitle: String? = nil
    public var onDismiss: () -> Void = {}

    @State private var selectedPreset: CourierThemePreset
    @State private var selectedWallpaper: CourierWallpaperPreset
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    public init(
        appearance: AppearancePreferences,
        activeRoomID: String? = nil,
        activeChatTitle: String? = nil,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.appearance = appearance
        self.activeRoomID = activeRoomID
        self.activeChatTitle = activeChatTitle
        self.onDismiss = onDismiss
        _selectedPreset = State(initialValue: appearance.themePreset)
        _selectedWallpaper = State(initialValue: appearance.defaultWallpaper)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Browse Chat Themes"))
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "Preview Courier’s built-in colour palettes and procedural vector wallpapers."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            previewBanner

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Theme Presets (8)"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(CourierThemePreset.allCases) { preset in
                        presetRow(preset)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Procedural Wallpapers (8)"))
                        .font(.subheadline.weight(.semibold))
                    ForEach(CourierWallpaperPreset.allCases) { wp in
                        wallpaperRow(wp)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack(spacing: 10) {
                Button(String(localized: "Use as Default Theme")) {
                    appearance.themePreset = selectedPreset
                    appearance.defaultWallpaper = selectedWallpaper
                }
                .buttonStyle(.borderedProminent)

                if let roomID = activeRoomID, !roomID.isEmpty {
                    let chatLabel = (activeChatTitle?.isEmpty == false) ? activeChatTitle! : String(localized: "Current Chat")
                    Button(String(localized: "Apply to \(chatLabel)")) {
                        var override = appearance.chatThemes[roomID] ?? ChatThemeOverride()
                        override.preset = selectedPreset
                        override.wallpaper = selectedWallpaper
                        appearance.setChatTheme(override, for: roomID)
                    }
                }

                Spacer(minLength: 8)

                Button(String(localized: "Close")) {
                    onDismiss()
                    dismiss()
                }
            }
        }
        .padding(18)
        .frame(minWidth: 640, idealWidth: 680, minHeight: 540)
    }

    private var previewBanner: some View {
        let isDark = colorScheme == .dark
        let outgoingHex = isDark ? selectedPreset.defaultOutgoingBubbleHexDark : selectedPreset.defaultOutgoingBubbleHexLight
        let incomingHex = isDark ? selectedPreset.defaultIncomingBubbleHexDark : selectedPreset.defaultIncomingBubbleHexLight
        let canvasHex = isDark ? selectedPreset.canvasTintHexDark : selectedPreset.canvasTintHexLight
        let outgoingColor = Color(hex: outgoingHex) ?? .accentColor
        let incomingColor = Color(hex: incomingHex) ?? Color.primary.opacity(0.10)
        let canvasColor = Color(hex: canvasHex) ?? Color(nsColor: .textBackgroundColor)

        return ZStack {
            canvasColor
            ChatWallpaperCanvasView(
                preset: selectedWallpaper,
                customImagePath: nil,
                opacity: max(0.28, appearance.wallpaperOpacity),
                blur: appearance.wallpaperBlur,
                reduceTransparency: appearance.reduceTransparency
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "Morning! Here’s how \(selectedPreset.title) looks with \(selectedWallpaper.title)."))
                        .font(.system(size: appearance.fontSizeScale.messageBodyPointSize))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14).fill(incomingColor))
                    Spacer(minLength: 40)
                }
                HStack {
                    Spacer(minLength: 40)
                    Text(String(localized: "Clean, readable, and 100% local on this Mac."))
                        .font(.system(size: appearance.fontSizeScale.messageBodyPointSize))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14).fill(outgoingColor))
                }
            }
            .padding(14)
        }
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func presetRow(_ preset: CourierThemePreset) -> some View {
        let isSelected = selectedPreset == preset
        let accent = Color(hex: preset.defaultAccentHex) ?? .accentColor
        return Button {
            selectedPreset = preset
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 14, height: 14)
                Text(preset.title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if appearance.themePreset == preset {
                    Text(String(localized: "Default"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.14) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }

    private func wallpaperRow(_ wp: CourierWallpaperPreset) -> some View {
        let isSelected = selectedWallpaper == wp
        return Button {
            selectedWallpaper = wp
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(wp.title)
                        .font(.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                    Text(wp.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Procedural vector wallpaper canvas rendered behind ConversationView and NoChatSelected (`EmptyStateBackground.tsx`,
/// `EmptyStateBackgroundThumbnail.tsx`).
public struct ChatWallpaperCanvasView: View {
    public let preset: CourierWallpaperPreset
    public let customImagePath: String?
    public let opacity: Double
    public let blur: Bool
    public let reduceTransparency: Bool

    @Environment(\.colorScheme) private var colorScheme

    public init(
        preset: CourierWallpaperPreset,
        customImagePath: String? = nil,
        opacity: Double = 0.25,
        blur: Bool = false,
        reduceTransparency: Bool = false
    ) {
        self.preset = preset
        self.customImagePath = customImagePath
        self.opacity = opacity
        self.blur = blur
        self.reduceTransparency = reduceTransparency
    }

    private var effectiveOpacity: Double {
        let clamped = min(1.0, max(0.0, opacity))
        return reduceTransparency ? min(0.12, clamped * 0.5) : clamped
    }

    public var body: some View {
        ZStack {
            if let path = customImagePath,
               !path.isEmpty,
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(effectiveOpacity)
                    .blur(radius: blur ? 8 : 0)
            } else if preset != .none {
                Canvas { context, size in
                    drawWallpaper(preset: preset, in: &context, size: size, isDark: colorScheme == .dark)
                }
                .opacity(effectiveOpacity)
                .blur(radius: blur ? 5 : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawWallpaper(
        preset: CourierWallpaperPreset,
        in context: inout GraphicsContext,
        size: CGSize,
        isDark: Bool
    ) {
        let strokeColor = isDark ? Color.white.opacity(0.32) : Color.black.opacity(0.24)
        let accentSecondary = isDark ? Color.cyan.opacity(0.28) : Color.teal.opacity(0.24)

        switch preset {
        case .none:
            break

        case .subtleGrid:
            let step: CGFloat = 24
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: 0.75)

        case .topographicLines:
            let lineCount = 9
            for idx in 0 ..< lineCount {
                var path = Path()
                let baseY = (size.height / CGFloat(lineCount)) * CGFloat(idx + 1) - 10
                path.move(to: CGPoint(x: 0, y: baseY))
                let segments = 16
                for seg in 1 ... segments {
                    let x = (size.width / CGFloat(segments)) * CGFloat(seg)
                    let wave1 = sin(Double(seg) * 0.65 + Double(idx) * 0.9) * 12.0
                    let wave2 = cos(Double(seg) * 0.35 - Double(idx) * 0.5) * 7.0
                    let y = baseY + CGFloat(wave1 + wave2)
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                context.stroke(path, with: .color(idx.isMultiple(of: 2) ? strokeColor : accentSecondary), lineWidth: 1.2)
            }

        case .softWaves:
            for idx in 0 ..< 6 {
                var path = Path()
                let baseY = size.height * (0.18 + CGFloat(idx) * 0.14)
                path.move(to: CGPoint(x: 0, y: baseY))
                let steps = 24
                for step in 1 ... steps {
                    let x = (size.width / CGFloat(steps)) * CGFloat(step)
                    let dy = sin(Double(step) * 0.45 + Double(idx) * 1.1) * 16.0
                    path.addLine(to: CGPoint(x: x, y: baseY + CGFloat(dy)))
                }
                context.stroke(path, with: .color(accentSecondary), lineWidth: 2.0)
            }

        case .starfield:
            let count = 48
            for idx in 0 ..< count {
                let seed = UInt32(idx &* 2_654_435_761)
                let fx = CGFloat(seed % 997) / 997.0
                let fy = CGFloat((seed >> 10) % 991) / 991.0
                let radius: CGFloat = (idx % 5 == 0) ? 2.4 : 1.4
                let rect = CGRect(
                    x: fx * size.width - radius,
                    y: fy * size.height - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                context.fill(Path(ellipseIn: rect), with: .color(idx % 3 == 0 ? accentSecondary : strokeColor))
            }

        case .auroraGlow:
            let bands: [(CGFloat, Color)] = [
                (0.25, Color.teal.opacity(0.35)),
                (0.55, Color.indigo.opacity(0.30)),
                (0.80, Color.mint.opacity(0.28)),
            ]
            for (fraction, bandColor) in bands {
                let rect = CGRect(
                    x: size.width * (fraction - 0.25),
                    y: size.height * 0.1,
                    width: size.width * 0.55,
                    height: size.height * 0.75
                )
                context.fill(Path(ellipseIn: rect), with: .color(bandColor))
            }

        case .dotMatrix:
            let spacing: CGFloat = 18
            var y: CGFloat = 10
            while y < size.height {
                var x: CGFloat = 10
                while x < size.width {
                    let dot = CGRect(x: x - 1.2, y: y - 1.2, width: 2.4, height: 2.4)
                    context.fill(Path(ellipseIn: dot), with: .color(strokeColor))
                    x += spacing
                }
                y += spacing
            }

        case .paperGrain:
            let step: CGFloat = 12
            var path = Path()
            var y: CGFloat = 4
            var row = 0
            while y < size.height {
                var x: CGFloat = (row.isMultiple(of: 2) ? 0 : 6)
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: min(size.width, x + 5), y: y))
                    x += step
                }
                y += 8
                row += 1
            }
            context.stroke(path, with: .color(strokeColor), lineWidth: 0.7)
        }
    }
}

/// Optional empty-state unread summary cards (`FeaturedHoneycombCard.tsx`, `UnreadThreadCard.tsx`) shown in `NoChatSelected`
/// when `appearance.showHoneycombCards` is enabled.
public struct EmptyStateUnreadCardsView: View {
    public let unreadRows: [CourierCore.InboxRow]
    public var redactNamesAndPictures: Bool = false
    public let onSelectRoom: (String) -> Void

    public init(
        unreadRows: [CourierCore.InboxRow],
        redactNamesAndPictures: Bool = false,
        onSelectRoom: @escaping (String) -> Void = { _ in }
    ) {
        self.unreadRows = unreadRows
        self.redactNamesAndPictures = redactNamesAndPictures
        self.onSelectRoom = onSelectRoom
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "hexagon.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                Text(
                    unreadRows.isEmpty
                        ? String(localized: "All caught up")
                        : String(localized: "\(unreadRows.count) Unread Conversations")
                )
                .font(.subheadline.weight(.semibold))
            }

            if unreadRows.isEmpty {
                Text(String(localized: "No unread messages waiting in your inbox."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(Array(unreadRows.prefix(4)), id: \.roomID) { row in
                        unreadCard(for: row)
                    }
                }
                .frame(maxWidth: 480)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    private func unreadCard(for row: CourierCore.InboxRow) -> some View {
        Button {
            onSelectRoom(row.roomID)
        } label: {
            let displayName = redactNamesAndPictures
                ? AppearancePreferences.redactedText(row.name, kind: .chatTitle)
                : (row.name.isEmpty ? String(localized: "Unnamed chat") : row.name)
            HStack(spacing: 10) {
                ChatAvatar(row: row)
                    .frame(width: 32, height: 32)
                    .blur(radius: redactNamesAndPictures ? 6 : 0)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if row.unread > 0 {
                            Text("\(row.unread)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor))
                        }
                    }
                    Text(row.preview.isEmpty ? String(localized: "New message") : row.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
