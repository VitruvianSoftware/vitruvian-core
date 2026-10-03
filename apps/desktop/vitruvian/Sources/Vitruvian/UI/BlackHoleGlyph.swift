// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import VitruvianCore
import VitruvianDesign
import VitruvianServices

/// The official mark, bundled as a template image so the idle state adapts to
/// light and dark menu bars. Active states can use real colors for attention.
/// A system symbol named in the menu bar settings can take the mark's place.
package enum BlackHoleGlyph {
    /// Logical size of the glyph in the menu bar, in points. Wide because the
    /// mark is ~1.97:1 and sized from its height. Tools/MakeIcon.swift writes
    /// the bundled PNGs at this size; `--selftest` checks the two still agree.
    package static let pointSize = NSSize(width: 26, height: 20)

    /// Requested ink height for the active states' system symbols. A compact
    /// symbol has to stand taller than the wide mark to read as the same size,
    /// matching the menu bar's other compact icons at ~15 pt. Antialiasing
    /// costs about a point of what is asked for here.
    private static let symbolHeight: CGFloat = 16

    /// Both scale representations go into one NSImage — loading the 1x file
    /// alone would render blurry on Retina menu bars. Read from disk once.
    private static let base: NSImage? = loadBase()

    private static func loadBase() -> NSImage? {
        let image = NSImage(size: pointSize)
        for resource in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data)
            else { continue }
            rep.size = pointSize
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }

    /// The symbol named in the menu bar settings, empty for the mark.
    package static var chosenSymbolName: String {
        Defaults.sanitizedMenuBarIconSymbol(
            UserDefaults.standard.string(forKey: DefaultsKey.menuBarIconSymbol))
    }

    /// What every state starts from: the chosen symbol, or the bundled mark
    /// when none is chosen or this Mac has no symbol by that name.
    package static func mark(symbolName: String = BlackHoleGlyph.chosenSymbolName) -> NSImage? {
        customMark(named: symbolName) ?? base
    }

    /// A system symbol on the canvas the active symbols use, or nil when
    /// this Mac has no symbol by that name: a typo, or a name from a newer
    /// macOS that came with a settings backup.
    package static func customMark(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        return fixedSizeSymbol(named: name)
    }

    package static func image(active: Bool) -> NSImage? {
        let tint = KeepAwakeIconTint.current
        guard active else { return mark() ?? fallback(active: false) }
        return activeImage(style: .current, tint: tint)
    }

    package static func activeImage(style: KeepAwakeActiveIcon,
                            tint: KeepAwakeIconTint = .orange) -> NSImage? {
        let source: NSImage?
        if let symbolName = style.systemSymbolName {
            source = fixedSizeSymbol(named: symbolName, drop: style.menuBarDrop)
        } else {
            source = mark()
        }
        guard let source else { return fallback(active: tint != .none) }
        guard let color = color(for: tint) else {
            source.isTemplate = true
            return source
        }
        return tintedImage(source, color: color) ?? fallback(active: true)
    }

    /// System symbols have different natural widths. Center them inside the
    /// same canvas as the app glyph so activation never shifts nearby items.
    ///
    /// Sized by the symbol's ink rather than its bounding box: SF Symbols pad
    /// their box by different amounts, so fitting the box leaves each style a
    /// different, smaller size than asked for.
    private static func fixedSizeSymbol(named name: String, drop: CGFloat = 0) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)),
              symbol.size.width > 0,
              symbol.size.height > 0,
              let ink = inkBounds(of: symbol),
              ink.width > 0, ink.height > 0 else { return nil }
        let scale = min(symbolHeight / ink.height, (pointSize.width - 2) / ink.width)
        let drawSize = NSSize(width: symbol.size.width * scale,
                              height: symbol.size.height * scale)
        // Offsets used to center the ink rather than the padded box.
        let inkOrigin = NSPoint(x: ink.minX * scale, y: ink.minY * scale)
        let inkSize = NSSize(width: ink.width * scale, height: ink.height * scale)
        let image = NSImage(size: pointSize, flipped: false) { rect in
            let target = NSRect(x: rect.midX - inkOrigin.x - inkSize.width / 2,
                                y: rect.midY - inkOrigin.y - inkSize.height / 2 - drop,
                                width: drawSize.width,
                                height: drawSize.height)
            symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Bounding box of an image's visible pixels, in its own (bottom-up) point
    /// space. Only runs when the menu bar icon changes, so rasterizing is cheap.
    private static func inkBounds(of image: NSImage) -> NSRect? {
        let sampling = 2
        let wide = Int(ceil(image.size.width)) * sampling
        let high = Int(ceil(image.size.height)) * sampling
        guard wide > 0, high > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The context comes from the rep's pixel dimensions, so it draws in
        // pixels; fill the whole bitmap and scale the bounds back down. A
        // point-sized rect here would only cover a corner of it.
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(wide), height: CGFloat(high)))
        NSGraphicsContext.restoreGraphicsState()

        var minX = wide, minY = high, maxX = -1, maxY = -1
        for y in 0..<high {
            for x in 0..<wide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // colorAt() reads top-down; NSImage coordinates run bottom-up.
        let unit = CGFloat(sampling)
        return NSRect(x: CGFloat(minX) / unit,
                      y: CGFloat(high - 1 - maxY) / unit,
                      width: CGFloat(maxX - minX + 1) / unit,
                      height: CGFloat(maxY - minY + 1) / unit)
    }

    /// A blue, full-strength glyph used to flag an available update. Non-template
    /// (a real color), drawn by masking blue into the glyph's shape.
    package static func attentionImage() -> NSImage? {
        guard let glyph = mark() else { return fallback(active: true) }
        return tintedImage(glyph, color: .systemBlue) ?? fallback(active: true)
    }

    /// The given state image with a red slashed microphone beside it, shown
    /// while the mute indicator option is on and the mic is muted. The badge
    /// is a real color, so the composite can't stay a template image; the
    /// drawing handler runs against the destination appearance, which keeps a
    /// template underlying glyph legible on both light and dark menu bars.
    package static func micMutedImage(over underlying: NSImage?) -> NSImage? {
        guard let underlying else { return nil }
        guard let badge = NSImage(systemSymbolName: "mic.slash.fill",
                                  accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) else { return nil }
        let gap: CGFloat = 2
        let badgeSize = badge.size
        let height = max(underlying.size.height, badgeSize.height)
        let size = NSSize(width: underlying.size.width + gap + badgeSize.width, height: height)
        let composed = NSImage(size: size, flipped: false) { _ in
            let glyphRect = NSRect(x: 0, y: (height - underlying.size.height) / 2,
                                   width: underlying.size.width, height: underlying.size.height)
            underlying.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)
            if underlying.isTemplate {
                // Template pixels carry no usable color of their own.
                NSColor.labelColor.setFill()
                glyphRect.fill(using: .sourceAtop)
            }
            let badgeRect = NSRect(x: underlying.size.width + gap,
                                   y: (height - badgeSize.height) / 2,
                                   width: badgeSize.width, height: badgeSize.height)
            badge.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.systemRed.setFill()
            badgeRect.fill(using: .sourceAtop)
            return true
        }
        composed.isTemplate = false
        return composed
    }

    private static func tintedImage(_ source: NSImage, color: NSColor) -> NSImage? {
        let tinted = NSImage(size: source.size, flipped: false) { rect in
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private static func color(for tint: KeepAwakeIconTint) -> NSColor? {
        switch tint {
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .none: return nil
        }
    }

    /// Keeps a recognizable presence if the bundled asset is ever missing
    /// (e.g. running the bare binary from build/).
    private static func fallback(active: Bool) -> NSImage? {
        if let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: active ? .bold : .regular)) {
            symbol.isTemplate = true
            return symbol
        }
        // Guaranteed last resort: draw a filled circle so the button always has a
        // visible, clickable image and can never become a zero-width, invisible item.
        let drawn = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        drawn.isTemplate = true
        return drawn
    }
}
