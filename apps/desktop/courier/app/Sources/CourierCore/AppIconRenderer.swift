// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit
import CoreGraphics
import Foundation

public enum CourierAppIconVariant: String, CaseIterable, Codable, Sendable, Identifiable {
    case classicTeal
    case midnightIndigo
    case sunsetAmber
    case emeraldForest
    case monochromeSlate
    case warmPaper
    case violetPulse
    case copperCraft

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .classicTeal: String(localized: "Classic Teal")
        case .midnightIndigo: String(localized: "Midnight Indigo")
        case .sunsetAmber: String(localized: "Sunset Amber")
        case .emeraldForest: String(localized: "Emerald Forest")
        case .monochromeSlate: String(localized: "Monochrome Slate")
        case .warmPaper: String(localized: "Warm Paper")
        case .violetPulse: String(localized: "Violet Pulse")
        case .copperCraft: String(localized: "Copper Craft")
        }
    }

    public var subtitle: String {
        switch self {
        case .classicTeal: String(localized: "Default ocean blue to teal gradient")
        case .midnightIndigo: String(localized: "Deep night indigo with luminous sky ink")
        case .sunsetAmber: String(localized: "Warm amber and coral horizon")
        case .emeraldForest: String(localized: "Rich pine and mint canopy")
        case .monochromeSlate: String(localized: "Graphite and silver studio finish")
        case .warmPaper: String(localized: "Parchment tile with deep ink glyph")
        case .violetPulse: String(localized: "Electric plum and orchid gradient")
        case .copperCraft: String(localized: "Burnished copper and terracotta")
        }
    }

    fileprivate struct Palette {
        let topRGB: (CGFloat, CGFloat, CGFloat)
        let bottomRGB: (CGFloat, CGFloat, CGFloat)
        let cardBackRGB: (CGFloat, CGFloat, CGFloat, CGFloat)
        let bubbleFillRGB: (CGFloat, CGFloat, CGFloat)
        let arrowStrokeRGB: (CGFloat, CGFloat, CGFloat)
        let badgeFillRGB: (CGFloat, CGFloat, CGFloat)
    }

    fileprivate var palette: Palette {
        switch self {
        case .classicTeal:
            return Palette(
                topRGB: (0.16, 0.36, 0.93),
                bottomRGB: (0.05, 0.66, 0.68),
                cardBackRGB: (0.85, 0.95, 1.0, 0.28),
                bubbleFillRGB: (1.0, 1.0, 1.0),
                arrowStrokeRGB: (0.10, 0.45, 0.82),
                badgeFillRGB: (0.06, 0.78, 0.66)
            )
        case .midnightIndigo:
            return Palette(
                topRGB: (0.12, 0.11, 0.38),
                bottomRGB: (0.24, 0.22, 0.66),
                cardBackRGB: (0.55, 0.62, 1.0, 0.26),
                bubbleFillRGB: (0.95, 0.96, 1.0),
                arrowStrokeRGB: (0.28, 0.26, 0.78),
                badgeFillRGB: (0.48, 0.56, 1.0)
            )
        case .sunsetAmber:
            return Palette(
                topRGB: (0.94, 0.33, 0.24),
                bottomRGB: (0.96, 0.62, 0.12),
                cardBackRGB: (1.0, 0.92, 0.80, 0.30),
                bubbleFillRGB: (1.0, 0.99, 0.97),
                arrowStrokeRGB: (0.86, 0.28, 0.16),
                badgeFillRGB: (0.99, 0.74, 0.18)
            )
        case .emeraldForest:
            return Palette(
                topRGB: (0.04, 0.38, 0.28),
                bottomRGB: (0.12, 0.68, 0.46),
                cardBackRGB: (0.78, 0.98, 0.88, 0.26),
                bubbleFillRGB: (0.97, 1.0, 0.98),
                arrowStrokeRGB: (0.06, 0.48, 0.34),
                badgeFillRGB: (0.20, 0.82, 0.56)
            )
        case .monochromeSlate:
            return Palette(
                topRGB: (0.18, 0.20, 0.24),
                bottomRGB: (0.36, 0.40, 0.46),
                cardBackRGB: (0.82, 0.85, 0.90, 0.24),
                bubbleFillRGB: (0.96, 0.97, 0.98),
                arrowStrokeRGB: (0.22, 0.25, 0.30),
                badgeFillRGB: (0.58, 0.64, 0.72)
            )
        case .warmPaper:
            return Palette(
                topRGB: (0.95, 0.91, 0.82),
                bottomRGB: (0.86, 0.79, 0.66),
                cardBackRGB: (0.32, 0.26, 0.20, 0.16),
                bubbleFillRGB: (0.20, 0.18, 0.15),
                arrowStrokeRGB: (0.95, 0.91, 0.82),
                badgeFillRGB: (0.78, 0.36, 0.20)
            )
        case .violetPulse:
            return Palette(
                topRGB: (0.44, 0.16, 0.78),
                bottomRGB: (0.78, 0.22, 0.68),
                cardBackRGB: (0.96, 0.82, 1.0, 0.28),
                bubbleFillRGB: (0.99, 0.97, 1.0),
                arrowStrokeRGB: (0.52, 0.18, 0.76),
                badgeFillRGB: (0.92, 0.36, 0.78)
            )
        case .copperCraft:
            return Palette(
                topRGB: (0.58, 0.25, 0.14),
                bottomRGB: (0.80, 0.44, 0.22),
                cardBackRGB: (1.0, 0.88, 0.78, 0.26),
                bubbleFillRGB: (0.99, 0.97, 0.95),
                arrowStrokeRGB: (0.62, 0.28, 0.15),
                badgeFillRGB: (0.90, 0.56, 0.28)
            )
        }
    }
}

public enum AppIconApplyError: LocalizedError, Equatable, Sendable {
    case invalidImageFile(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidImageFile(let path):
            String(localized: "Couldn’t load an icon image from “\(path)”. Choose a valid PNG, JPG, or ICNS file.")
        }
    }
}

@MainActor
public protocol AppIconApplying: AnyObject {
    var appliedVariant: CourierAppIconVariant? { get }
    var appliedCustomPath: String? { get }
    func apply(variant: CourierAppIconVariant)
    func applyCustomImage(at path: String) throws
}

@MainActor
public final class MACAppIconApplier: AppIconApplying {
    public private(set) var appliedVariant: CourierAppIconVariant?
    public private(set) var appliedCustomPath: String?

    nonisolated public init() {}

    public func apply(variant: CourierAppIconVariant) {
        appliedVariant = variant
        appliedCustomPath = nil
        if let app = NSApp {
            app.applicationIconImage = AppIconRenderer.renderIcon(variant: variant, size: 256)
        }
    }

    public func applyCustomImage(at path: String) throws {
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
        if let app = NSApp {
            app.applicationIconImage = image
        }
    }
}

public enum AppIconRenderer {
    /// Draws our own clean-room procedural vector Courier app icon (rounded squircle + stacked message cards + speech bubble with forward arrow + accent badge)
    /// at the requested pixel dimension (e.g. 128, 256, 512, 1024). Zero external asset files.
    public static func renderIcon(variant: CourierAppIconVariant, size: Int = 256) -> NSImage {
        let clampedSize = max(32, size)
        let s = CGFloat(clampedSize)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: clampedSize,
            height: clampedSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: NSSize(width: clampedSize, height: clampedSize))
        }

        context.scaleBy(x: s / 1024.0, y: s / 1024.0)
        let palette = variant.palette

        // 1. Rounded macOS squircle tile (margin 100 of 1024)
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.28))
        context.addPath(tilePath)
        context.setFillColor(
            CGColor(
                srgbRed: palette.topRGB.0,
                green: palette.topRGB.1,
                blue: palette.topRGB.2,
                alpha: 1
            )
        )
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: space,
            colors: [
                CGColor(srgbRed: palette.topRGB.0, green: palette.topRGB.1, blue: palette.topRGB.2, alpha: 1),
                CGColor(srgbRed: palette.bottomRGB.0, green: palette.bottomRGB.1, blue: palette.bottomRGB.2, alpha: 1),
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 100, y: 924),
                end: CGPoint(x: 924, y: 100),
                options: []
            )
        }

        // 2. Stacked rear message card for depth
        let backCard = CGPath(
            roundedRect: CGRect(x: 270, y: 390, width: 510, height: 360),
            cornerWidth: 120,
            cornerHeight: 120,
            transform: nil
        )
        context.addPath(backCard)
        context.setFillColor(
            CGColor(
                srgbRed: palette.cardBackRGB.0,
                green: palette.cardBackRGB.1,
                blue: palette.cardBackRGB.2,
                alpha: palette.cardBackRGB.3
            )
        )
        context.fillPath()
        context.restoreGState()

        // 3. Foreground speech bubble with lower-left tail
        let bubble = CGMutablePath()
        bubble.addRoundedRect(in: CGRect(x: 240, y: 320, width: 544, height: 400), cornerWidth: 150, cornerHeight: 150)
        bubble.move(to: CGPoint(x: 300, y: 370))
        bubble.addLine(to: CGPoint(x: 250, y: 245))
        bubble.addLine(to: CGPoint(x: 420, y: 330))
        bubble.closeSubpath()
        context.addPath(bubble)
        context.setFillColor(
            CGColor(
                srgbRed: palette.bubbleFillRGB.0,
                green: palette.bubbleFillRGB.1,
                blue: palette.bubbleFillRGB.2,
                alpha: 1
            )
        )
        context.fillPath()

        // 4. Courier forward arrow inside the bubble
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 370, y: 520))
        arrow.addLine(to: CGPoint(x: 610, y: 520))
        arrow.move(to: CGPoint(x: 540, y: 600))
        arrow.addLine(to: CGPoint(x: 630, y: 520))
        arrow.addLine(to: CGPoint(x: 540, y: 440))
        context.addPath(arrow)
        context.setStrokeColor(
            CGColor(
                srgbRed: palette.arrowStrokeRGB.0,
                green: palette.arrowStrokeRGB.1,
                blue: palette.arrowStrokeRGB.2,
                alpha: 1
            )
        )
        context.setLineWidth(56)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()

        // 5. Accent status dot in upper-right of the bubble
        let badgeRect = CGRect(x: 690, y: 630, width: 96, height: 96)
        context.fillEllipse(in: badgeRect)
        context.saveGState()
        context.setFillColor(
            CGColor(
                srgbRed: palette.badgeFillRGB.0,
                green: palette.badgeFillRGB.1,
                blue: palette.badgeFillRGB.2,
                alpha: 1
            )
        )
        context.fillEllipse(in: badgeRect.insetBy(dx: 10, dy: 10))
        context.restoreGState()

        guard let cgImage = context.makeImage() else {
            return NSImage(size: NSSize(width: clampedSize, height: clampedSize))
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: clampedSize, height: clampedSize))
    }
}
